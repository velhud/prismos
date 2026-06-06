# PrismOS Canonical Identifiers (v1)

This file is the source of truth for identifiers used across:
- on-device code (`kernel.py`, `apps/*`, `prism/*`)
- semantic JSON schemas (`Documentation/data_scheme.md`)
- app specifications (`Documentation/apps/*.md`)

---

## 1) App IDs (APP_ID)

APP_ID is a short lowercase token used everywhere (kernel registry, protocol routing, host->device envelopes).

Allowed APP_ID values (v1 registry):
- `oracle`
- `vision`
- `navigate`
- `stream`
- `chronos`
- `teleprompter`
- `recall`
- `babel`

Rule:
- App specs must list **Internal ID** as one of these exact values (no prefix like `app.`).

Active host carousel:
- `oracle`
- `vision`
- `stream`
- `chronos`
- `teleprompter`
- `babel`

Archived prototypes:
- `navigate`
- `recall`

---

## 2) Message Types (`type` field in CTRL_JSON payloads)

Allowed `type` values:
- `SYS`   — system commands (routing + orbit widgets)
- `STATE` — active app state update (host → device)
- `GHOST` — ghost overlay update (host → device)
- `ERR`   — global error/toast (host → device)

---

## 3) System Commands (`SYS.cmd`)

Allowed `SYS.cmd` values:
- `FOCUS`   — request device focus a specific app by APP_ID
- `WIDGETS` — update orbit widgets (app_id -> short text)
- `TIME`    — set device wall-clock time (epoch seconds + optional timezone offset)

---

## 4) Button Event Envelope (device → host)

Device emits button events as CTRL_JSON payloads in this shape:

```json
{
  "event": "BTN",
  "id": "L",
  "gesture": "TAP",
  "app": "oracle",
  "ts": 123456
}
````

Rules:

* `id` is physical side only: `L` or `R`
* `gesture` is: `TAP` | `LONG` | `DOUBLE`
* `app` is:

  * `null` (or omitted) while in orbit
  * the active APP_ID while focused (e.g., `oracle`)
* `ts` is monotonic milliseconds (`time.ticks_ms()`), intended for debugging and ordering.

## 5) Focus Event Envelope (device → host)

Device emits focus transition events whenever it enters an app or returns to Orbit:

```json
{
  "event": "FOCUS",
  "mode": "FOCUS",      // "FOCUS" when entering an app, "ORBIT" when leaving to Orbit
  "app": "vision",      // current focused app id, or null in ORBIT
  "prev": "oracle",     // previous focused app id, or null
  "ts": 123456          // monotonic ms (time.ticks_ms)
}
````
