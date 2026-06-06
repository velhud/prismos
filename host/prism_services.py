"""Host-side service adapters for real PrismOS apps.

The Monocle firmware stays a thin hardware client. This module owns host data
sources, optional cloud calls, clipboard access, and capture persistence.
It intentionally uses only the Python standard library so the BLE harness keeps
working in a clean checkout.
"""

import base64
import json
import mimetypes
import os
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path


HOST_DIR = Path(__file__).resolve().parent
DATA_DIR = HOST_DIR / "data"
CAPTURE_DIR = HOST_DIR / "captures"


DEFAULT_ORACLE_PROMPT = "Give me one useful, concrete tip for the conversation I am in."
DEFAULT_TELEPROMPTER = [
    "Welcome everyone.",
    "I will keep this short.",
    "Here is the problem.",
    "Here is the decision.",
    "Here is the next step.",
    "Thank you.",
]
DEFAULT_STREAM_CARDS = [
    {"source": "SYS", "title": "HOST READY", "body": "Monocle link active", "prio": "IMPORTANT", "handoff": False},
    {"source": "CAL", "title": "NEXT EVENT", "body": "Check calendar bridge", "prio": "INFO", "handoff": True},
]
DEFAULT_BABEL_TEXT = "Sumimasen, platform two wa doko desu ka?"


def clean_for_screen(value, limit=900):
    text = "" if value is None else str(value)
    text = text.replace("\r", " ").replace("\n", " ")
    text = " ".join(text.split())
    return text[:limit]


def wrap_plain_text(value, cols=24, max_lines=200):
    words = clean_for_screen(value, limit=12000).split()
    lines = []
    current = ""
    for word in words:
        if len(lines) >= max_lines:
            break
        if len(word) > cols:
            if current:
                lines.append(current)
                current = ""
            while len(word) > cols and len(lines) < max_lines:
                lines.append(word[:cols])
                word = word[cols:]
            if word:
                current = word
        elif not current:
            current = word
        elif len(current) + 1 + len(word) <= cols:
            current += " " + word
        else:
            lines.append(current)
            current = word
    if current and len(lines) < max_lines:
        lines.append(current)
    return lines


def load_env_file(path):
    if not path:
        return
    p = Path(path).expanduser()
    if not p.exists() or not p.is_file():
        return
    try:
        for raw in p.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value
    except Exception:
        return


class OpenAIProvider:
    """Minimal OpenAI REST adapter using Responses + Audio endpoints."""

    def __init__(self):
        load_env_file(os.environ.get("PRISM_ENV_FILE"))
        self.api_key = os.environ.get("OPENAI_API_KEY", "").strip()
        self.base_url = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
        self.text_model = os.environ.get("PRISM_OPENAI_MODEL", "gpt-5.5")
        self.vision_model = os.environ.get("PRISM_OPENAI_VISION_MODEL", self.text_model)
        self.translate_model = os.environ.get("PRISM_OPENAI_TRANSLATE_MODEL", self.text_model)
        self.transcribe_model = os.environ.get("PRISM_OPENAI_TRANSCRIBE_MODEL", "gpt-4o-mini-transcribe")
        self.reasoning_effort = os.environ.get("PRISM_OPENAI_REASONING", "low")
        self.verbosity = os.environ.get("PRISM_OPENAI_VERBOSITY", "low")
        self.timeout = float(os.environ.get("PRISM_OPENAI_TIMEOUT", "30"))
        self.last_error = ""

    def available(self):
        return bool(self.api_key)

    def _headers(self, content_type="application/json"):
        return {
            "Authorization": "Bearer " + self.api_key,
            "Content-Type": content_type,
        }

    def _post_json(self, path, body):
        if not self.available():
            raise RuntimeError("OPENAI_API_KEY is not configured")
        data = json.dumps(body, separators=(",", ":")).encode("utf-8")
        req = urllib.request.Request(
            self.base_url + path,
            data=data,
            headers=self._headers(),
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def _response_body(self, model, max_output_tokens=220, store=False):
        body = {
            "model": model,
            "max_output_tokens": int(max_output_tokens),
            "store": bool(store),
        }
        if str(model).startswith("gpt-5"):
            body["reasoning"] = {"effort": self.reasoning_effort}
            body["text"] = {"verbosity": self.verbosity}
        return body

    def _extract_text(self, response):
        if isinstance(response.get("output_text"), str):
            return response["output_text"]
        out = []
        for item in response.get("output", []) or []:
            for part in item.get("content", []) or []:
                if isinstance(part, dict) and isinstance(part.get("text"), str):
                    out.append(part["text"])
        text = clean_for_screen(" ".join(out), limit=2400)
        if not text:
            text = "No text returned by provider."
        return text

    def _safe_call(self, fn, fallback):
        try:
            self.last_error = ""
            return fn()
        except urllib.error.HTTPError as exc:
            detail = ""
            try:
                detail = exc.read().decode("utf-8", "ignore")
            except Exception:
                detail = str(exc)
            self.last_error = clean_for_screen(detail or exc, limit=220)
            return fallback
        except Exception as exc:
            self.last_error = clean_for_screen(exc, limit=220)
            return fallback

    def answer(self, prompt, context=""):
        prompt = clean_for_screen(prompt, limit=1800)
        context = clean_for_screen(context, limit=1200)
        system = (
            "You are Jack running on a Mac host for a Brilliant Labs Monocle. "
            "Answer for a tiny heads-up display: direct, concrete, no markdown, "
            "prefer 2-5 short sentences unless the user asks otherwise."
        )
        if context:
            prompt = "Context: %s\n\nQuestion: %s" % (context, prompt)

        def call():
            body = self._response_body(self.text_model, max_output_tokens=260, store=False)
            body.update({
                "instructions": system,
                "input": prompt,
            })
            return self._extract_text(self._post_json("/responses", body))

        fallback = "Provider offline. Host prompt: " + prompt[:180]
        return self._safe_call(call, fallback)

    def vision(self, image_bytes, prompt="Identify what matters in this image.", mime_type="image/jpeg"):
        if not image_bytes:
            return "No image bytes received."
        b64 = base64.b64encode(bytes(image_bytes)).decode("ascii")
        data_url = "data:%s;base64,%s" % (mime_type, b64)

        def call():
            body = self._response_body(self.vision_model, max_output_tokens=220, store=False)
            body.update({
                "input": [{
                    "role": "user",
                    "content": [
                        {"type": "input_text", "text": clean_for_screen(prompt, limit=700)},
                        {"type": "input_image", "image_url": data_url, "detail": "low"},
                    ],
                }],
            })
            return self._extract_text(self._post_json("/responses", body))

        fallback = "Provider offline. Captured %d image bytes for host analysis." % (len(image_bytes),)
        return self._safe_call(call, fallback)

    def translate(self, text, src="AUTO", dst="EN"):
        text = clean_for_screen(text, limit=1800)
        system = (
            "Translate speech for a tiny wearable subtitle display. "
            "Return only the translation, short and natural. No notes."
        )

        def call():
            body = self._response_body(self.translate_model, max_output_tokens=160, store=False)
            body.update({
                "instructions": system,
                "input": "Source language: %s\nTarget language: %s\nText: %s" % (src, dst, text),
            })
            return self._extract_text(self._post_json("/responses", body))

        fallback = "[%s>%s] %s" % (src, dst, text)
        return self._safe_call(call, fallback)

    def transcribe_s8_pcm(self, audio_bytes, sample_rate=8000):
        wav = pcm_s8_to_wav16(audio_bytes, sample_rate=sample_rate)
        return self.transcribe_file(wav, filename="monocle.wav", mime_type="audio/wav")

    def transcribe_u8_pcm(self, audio_bytes, sample_rate=8000):
        return self.transcribe_s8_pcm(audio_bytes, sample_rate=sample_rate)

    def transcribe_file(self, audio_bytes, filename="audio.wav", mime_type="audio/wav"):
        if not self.available():
            self.last_error = "OPENAI_API_KEY is not configured"
            return ""
        boundary = "----prismos%d" % int(time.time() * 1000)
        body = bytearray()

        def field(name, value):
            body.extend(("--%s\r\n" % boundary).encode("ascii"))
            body.extend(('Content-Disposition: form-data; name="%s"\r\n\r\n' % name).encode("ascii"))
            body.extend(str(value).encode("utf-8"))
            body.extend(b"\r\n")

        field("model", self.transcribe_model)
        body.extend(("--%s\r\n" % boundary).encode("ascii"))
        body.extend(('Content-Disposition: form-data; name="file"; filename="%s"\r\n' % filename).encode("ascii"))
        body.extend(("Content-Type: %s\r\n\r\n" % mime_type).encode("ascii"))
        body.extend(bytes(audio_bytes))
        body.extend(b"\r\n")
        body.extend(("--%s--\r\n" % boundary).encode("ascii"))

        try:
            req = urllib.request.Request(
                self.base_url + "/audio/transcriptions",
                data=bytes(body),
                headers=self._headers("multipart/form-data; boundary=%s" % boundary),
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                obj = json.loads(resp.read().decode("utf-8"))
            self.last_error = ""
            return clean_for_screen(obj.get("text", ""), limit=1800)
        except Exception as exc:
            self.last_error = clean_for_screen(exc, limit=220)
            return ""


def pcm_s8_to_wav16(audio_bytes, sample_rate=8000, channels=1):
    data = bytes(audio_bytes or b"")
    sample_rate = int(sample_rate)
    channels = int(channels)
    sample_width = 2
    byte_rate = sample_rate * channels * sample_width
    block_align = channels * sample_width
    pcm = bytearray()
    for raw in data:
        sample = raw if raw < 128 else raw - 256
        pcm.extend(int(sample * 256).to_bytes(2, "little", signed=True))
    header = bytearray()
    header.extend(b"RIFF")
    header.extend((36 + len(pcm)).to_bytes(4, "little"))
    header.extend(b"WAVEfmt ")
    header.extend((16).to_bytes(4, "little"))
    header.extend((1).to_bytes(2, "little"))
    header.extend(channels.to_bytes(2, "little"))
    header.extend(sample_rate.to_bytes(4, "little"))
    header.extend(byte_rate.to_bytes(4, "little"))
    header.extend(block_align.to_bytes(2, "little"))
    header.extend((16).to_bytes(2, "little"))
    header.extend(b"data")
    header.extend(len(pcm).to_bytes(4, "little"))
    header.extend(pcm)
    return bytes(header)


def pcm_u8_to_wav(audio_bytes, sample_rate=8000, channels=1):
    return pcm_s8_to_wav16(audio_bytes, sample_rate=sample_rate, channels=channels)


class HostData:
    def __init__(self):
        self.data_dir = Path(os.environ.get("PRISM_DATA_DIR", str(DATA_DIR))).expanduser()
        self.capture_dir = Path(os.environ.get("PRISM_CAPTURE_DIR", str(CAPTURE_DIR))).expanduser()

    def _read_text_file(self, path, limit=8000):
        if not path:
            return ""
        p = Path(path).expanduser()
        if not p.exists() or not p.is_file():
            return ""
        try:
            return p.read_text(encoding="utf-8", errors="ignore")[:limit]
        except Exception:
            return ""

    def clipboard_text(self, limit=1800):
        try:
            proc = subprocess.run(
                ["pbpaste"],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=0.5,
            )
            if proc.returncode != 0:
                return ""
            return clean_for_screen(proc.stdout.decode("utf-8", "ignore"), limit=limit)
        except Exception:
            return ""

    def write_clipboard(self, text):
        try:
            subprocess.run(
                ["pbcopy"],
                input=clean_for_screen(text, limit=10000).encode("utf-8"),
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=0.7,
            )
            return True
        except Exception:
            return False

    def oracle_prompt(self):
        env_prompt = clean_for_screen(os.environ.get("PRISM_ORACLE_PROMPT", ""), limit=1800)
        if env_prompt:
            return env_prompt, "ENV"
        path = os.environ.get("PRISM_ORACLE_PROMPT_FILE") or str(self.data_dir / "oracle_prompt.txt")
        file_prompt = clean_for_screen(self._read_text_file(path), limit=1800)
        if file_prompt:
            return file_prompt, "FILE"
        clip = self.clipboard_text(limit=1800)
        if clip:
            return clip, "CLIP"
        return DEFAULT_ORACLE_PROMPT, "DEFAULT"

    def teleprompter_lines(self):
        path = os.environ.get("PRISM_TELEPROMPTER_FILE") or str(self.data_dir / "teleprompter.txt")
        raw = self._read_text_file(path, limit=12000)
        lines = []
        for line in raw.splitlines():
            cleaned = clean_for_screen(line, limit=500)
            if cleaned:
                lines.extend(wrap_plain_text(cleaned, cols=24, max_lines=200 - len(lines)))
        return lines or list(DEFAULT_TELEPROMPTER)

    def stream_cards(self):
        path = os.environ.get("PRISM_STREAM_FILE") or str(self.data_dir / "stream_cards.json")
        raw = self._read_text_file(path, limit=20000)
        cards = []
        if raw:
            try:
                data = json.loads(raw)
                cards = data if isinstance(data, list) else data.get("cards", [])
            except Exception:
                cards = []
        if not cards:
            cards = DEFAULT_STREAM_CARDS
        return [self._clean_card(card) for card in cards if isinstance(card, dict)]

    def chronos_seconds(self):
        raw = os.environ.get("PRISM_CHRONOS_SECONDS", "")
        try:
            seconds = int(raw)
        except Exception:
            seconds = 300
        return max(10, min(24 * 60 * 60, seconds))

    def _clean_card(self, card):
        prio = str(card.get("prio", "INFO")).upper()
        if prio not in ("CRITICAL", "IMPORTANT", "INFO"):
            prio = "INFO"
        return {
            "source": clean_for_screen(card.get("source", "SYS"), limit=4).upper(),
            "title": clean_for_screen(card.get("title", "CARD"), limit=40).upper(),
            "body": clean_for_screen(card.get("body", ""), limit=120),
            "prio": prio,
            "handoff": bool(card.get("handoff", False)),
        }

    def babel_text(self):
        env_text = clean_for_screen(os.environ.get("PRISM_BABEL_TEXT", ""), limit=1800)
        if env_text:
            return env_text, "ENV"
        path = os.environ.get("PRISM_BABEL_TEXT_FILE") or str(self.data_dir / "babel_text.txt")
        file_text = clean_for_screen(self._read_text_file(path), limit=1800)
        if file_text:
            return file_text, "FILE"
        clip = self.clipboard_text(limit=1800)
        if clip:
            return clip, "CLIP"
        return DEFAULT_BABEL_TEXT, "DEFAULT"

    def save_capture(self, image_bytes, msg_id=None, ext=".jpg"):
        self.capture_dir.mkdir(parents=True, exist_ok=True)
        stamp = int(time.time() * 1000)
        mid = "x" if msg_id is None else str(msg_id)
        path = self.capture_dir / ("capture_%s_%d%s" % (mid, stamp, ext))
        path.write_bytes(bytes(image_bytes or b""))
        return str(path)

    def append_jsonl(self, filename, record):
        self.data_dir.mkdir(parents=True, exist_ok=True)
        path = self.data_dir / filename
        data = dict(record or {})
        data.setdefault("ts", int(time.time()))
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(data, separators=(",", ":"), ensure_ascii=False))
            f.write("\n")
        return str(path)

    def save_oracle_history(self, prompt, answer, source=""):
        return self.append_jsonl("oracle_history.jsonl", {
            "kind": "oracle",
            "source": clean_for_screen(source, limit=40),
            "prompt": clean_for_screen(prompt, limit=1800),
            "answer": clean_for_screen(answer, limit=2400),
        })

    def save_vision_note(self, result, capture_path="", mode="IDENTIFY"):
        return self.append_jsonl("vision_notes.jsonl", {
            "kind": "vision",
            "mode": clean_for_screen(mode, limit=20),
            "capture": clean_for_screen(capture_path, limit=500),
            "result": clean_for_screen(result, limit=1800),
        })

    def save_babel_transcript(self, lines, src="AUTO", dst="EN"):
        cleaned = []
        for kind, text in list(lines or [])[-40:]:
            cleaned.append({
                "kind": clean_for_screen(kind, limit=12),
                "text": clean_for_screen(text, limit=360),
            })
        return self.append_jsonl("babel_transcripts.jsonl", {
            "kind": "babel",
            "src": clean_for_screen(src, limit=12),
            "dst": clean_for_screen(dst, limit=12),
            "lines": cleaned,
        })

    def mime_for_path(self, path, default="image/jpeg"):
        mime, _ = mimetypes.guess_type(str(path))
        return mime or default


class HostServices:
    def __init__(self, provider=None, data=None):
        self.provider = provider or OpenAIProvider()
        self.data = data or HostData()

    def status(self):
        return "OPENAI" if self.provider.available() else "OFFLINE"

    def answer_oracle(self, prompt, context=""):
        return self.provider.answer(prompt, context=context)

    def analyze_image(self, image_bytes, prompt=None, mime_type="image/jpeg"):
        return self.provider.vision(
            image_bytes,
            prompt=prompt or "Identify what matters. Include any readable text and one suggested action.",
            mime_type=mime_type,
        )

    def translate_text(self, text, src="AUTO", dst="EN"):
        return self.provider.translate(text, src=src, dst=dst)

    def transcribe_audio(self, audio_bytes, sample_rate=8000):
        return self.provider.transcribe_s8_pcm(audio_bytes, sample_rate=sample_rate)
