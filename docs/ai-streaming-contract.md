# AI Streaming Contract — `smart-api` SSE

Single source of truth for how the `smart-api` edge function streams the assistant's
reply, and how clients consume it. **Client-agnostic** — both the Flutter app
(`stockai/lib/services/api_service.dart`) and the web widget (`website/ai-assistant-v4.js`)
code against this same contract.

Status: **spec approved; backend implementation pending** (gated on the cleanup deploy).
Until the streaming branch ships, clients that send `stream:true` still receive the
legacy JSON response, so front-ends can be written ahead of time and flip the flag later.

---

## 1. Why

`smart-api` runs a Claude tool-use loop (up to 8 iterations) and today returns the
**entire** reply in one JSON body after the loop finishes. The chat shows a dead wait,
then a wall of text. Streaming makes the reply type out live (and the assistant's
"let me check…" preamble appears before a tool runs).

## 2. Opt-in (backward compatible)

- To stream, send `"stream": true` in the POST body. Everything else
  (`message`, `context`, `inventory`) is unchanged.
- Omit `stream` (or send `false`) → **unchanged** legacy JSON response
  `{ content, message, refresh, navigate }`.
- **Direct tool-call mode** (`body.tool_call`) is **never** streamed — it returns
  JSON as today.
- Auth is unchanged: call `refreshSession()` first, send `Authorization: Bearer <jwt>`
  + `apikey`. JWT gateway enforcement runs **before** the stream opens; an invalid
  token returns a `401` JSON body, not a stream.

## 3. Response

On the streaming path the response is `Content-Type: text/event-stream` (plus the usual
CORS headers). The body is a sequence of Server-Sent Events. Each event is:

```
event: <type>
data: <single-line JSON>

```

(blank line terminates each event). Periodic `: keep-alive` comment lines are sent
(~every 15s) to defeat proxy/edge idle timeouts — **ignore** them.

### Event types

| `event:` | `data` JSON | Meaning / client action |
|----------|-------------|-------------------------|
| `start`  | `{}` | Stream opened. Optionally show a typing indicator. |
| `token`  | `{"text":"…chunk…"}` | A **delta** of assistant text. **Append** it to the current bubble. (Concatenate deltas — they are not cumulative.) |
| `tool`   | `{"name":"create_category","status":"running"\|"done"\|"error"}` | Optional UI hint, e.g. "Assistant is creating a category…". Not required to render. |
| `turn`   | `{"index":N,"stop_reason":"tool_use"\|"end_turn"}` | Turn boundary. Lets the UI separate pre-tool "thinking" text from the final answer if desired. |
| `done`   | `{"message":"<full final text>","refresh":bool,"navigate":string\|null}` | **Terminal.** `message` is the canonical full text — reconcile against streamed tokens. Then apply `refresh` / `navigate` exactly as with the legacy JSON response. Stream closes after this. |
| `error`  | `{"error":"…"}` | Failure. Show the error and stop. Stream closes after this. |

### Metadata

- `refresh` — aggregated across all tool calls in the turn; delivered in `done`.
  Trigger any UI/data refresh **after** rendering the final text.
- `navigate` — parsed from the final text (e.g. `inventory.html?table=foo`); delivered
  in `done`. Same handling as today.
- Tool results themselves are **internal** and never sent to the client; only the
  human-friendly `tool` status hint is exposed.

## 4. Server behavior (summary)

- The tool-use loop is unchanged; **every** Anthropic call is made with `stream:true`
  (we can't predict which turn ends with `end_turn`).
- Anthropic's stream is parsed server-side:
  - `content_block_delta` / `text_delta` → emit `token`.
  - `content_block_start` (tool_use) + `input_json_delta` fragments → accumulate, then
    `JSON.parse` at `content_block_stop`.
  - `message_delta.stop_reason`:
    - `tool_use` → emit `tool`, run the tool via the existing `runTool` (ownership checks
      intact), append `tool_result`, loop again.
    - `end_turn` → emit `done`, close.
- 8-iteration cap retained. JWT + per-tool ownership checks unchanged.
- The streaming branch is **additive** — the non-streaming and direct `tool_call`
  paths are left intact.

## 5. Client consumption sketches

### Flutter (`api_service.dart`)
```dart
// Stream<ChatEvent> streamMessage(...)
final req = http.Request('POST', uri)
  ..headers.addAll(headers)            // Bearer + apikey, after refreshSession()
  ..body = jsonEncode({...payload, 'stream': true});
final res = await http.Client().send(req);
await for (final line in res.stream
    .transform(utf8.decoder)
    .transform(const LineSplitter())) {
  // parse `event:` / `data:` lines into ChatEvent; append on token, finalize on done
}
```

### Web (`ai-assistant-v4.js`)
```js
const res = await fetch(url, { method: 'POST', headers, body: JSON.stringify({ ...payload, stream: true }) });
const reader = res.body.getReader();
const dec = new TextDecoder();
// read chunks, split on \n\n, parse event:/data:, append on token, finalize on done
```

## 6. Open items

- Front-ends: confirm delta-append semantics suit your renderer (TTS may want to start
  only on `done`; flag if you need a dedicated signal).
- Heartbeat interval may be tuned once we observe real edge/proxy timeouts.
