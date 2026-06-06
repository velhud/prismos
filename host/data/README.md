# PrismOS Host Data

These files let the desktop Host run practical app flows without code edits.

- `oracle_prompt.txt`: silent prompt fallback used by Oracle `Hold R` when `PRISM_ORACLE_PROMPT` and clipboard input are not set.
- `teleprompter.txt`: line-by-line script loaded by Teleprompter.
- `babel_text.txt`: text fallback translated by Babel `Double R`.
- `stream_cards.json`: Signal cards. Each card supports `source`, `title`, `body`, `prio`, and `handoff`.

Useful runtime overrides:

- `PRISM_ENV_FILE`: `.env` file containing `OPENAI_API_KEY` and model overrides.
- `PRISM_DATA_DIR`: alternate directory for these app data files.
- `PRISM_CAPTURE_DIR`: Vision JPEG output directory.
- `PRISM_ORACLE_PROMPT`: one-shot Oracle prompt text.
- `PRISM_OPENAI_MODEL`: Oracle model, default `gpt-5.5`.
- `PRISM_OPENAI_VISION_MODEL`: Vision model, default same as `PRISM_OPENAI_MODEL`.
- `PRISM_OPENAI_TRANSLATE_MODEL`: Babel translation model, default same as `PRISM_OPENAI_MODEL`.
- `PRISM_OPENAI_TRANSCRIBE_MODEL`: Babel audio transcription model, default `gpt-4o-mini-transcribe`.
- `PRISM_CHRONOS_SECONDS`: default Chronos timer length, default `300`.

Runtime output files:

- `oracle_history.jsonl`: Oracle prompt/answer records.
- `vision_notes.jsonl`: saved Vision results and capture paths.
- `babel_transcripts.jsonl`: saved Babel subtitle buffers.

No-hardware smoke test:

```bash
python3 host/prism_host.py --dry-run
```
