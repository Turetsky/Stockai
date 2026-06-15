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
  + `apikey`. JWT gateway enforcement **and** the function's `getUser` validation both run
  **before** the stream opens, so **session expiry / invalid token = a plain HTTP `401`
  JSON response, never an SSE `error` event**. Clients keep their existing
  401→`refreshSession()`/`SessionExpiredException` retry path on the initial response.
  The SSE `error` event is reserved for mid-stream failures only (Anthropic/network/tool),
  not auth — handling it is a defensive fallback, not required for expiry.

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
| `token`  | `{"text":"…chunk…"}` | A **delta** of assistant text. **Append** it to the current answer bubble. (Concatenate deltas — they are not cumulative.) Tokens stream live from **any** turn, including short "let me check…" narration a turn may emit *before* it calls a tool — see the reset rule on `turn` below. |
| `tool`   | `{"name":"<raw tool name>","status":"running"\|"done"\|"error"}` | UI hint. `name` is the **raw tool name** (`list_categories`, `get_items`, `get_fields`, `create_category`, `rename_category`, `delete_category`, `add_field`, `remove_field`, `rename_field`, `upsert_item`, `delete_item`, `get_ui_settings`, `set_ui_setting`, `set_layout`) — these are **stable/part of the contract**. Lifecycle: `running` emitted **before** the tool executes, then `done`/`error` **after**; one pair per tool, in order, if a turn calls several. Clients map `name`→a friendly label (e.g. `get_items`→"Checking inventory…") with a generic "Working…" fallback. Pairs well with the `turn` reset rule to mask the bubble-clear with a status chip. Not required to render. |
| `turn`   | `{"index":N,"stop_reason":"tool_use"\|"end_turn"}` | Turn boundary. **Reset rule:** on `stop_reason:"tool_use"`, **discard the text appended during that turn** (it was pre-tool "thinking", not the answer) and clear the bubble. The user-facing answer is the text streamed **after the last tool turn** (the turn that ends `end_turn`). This lets a client append every `token` blindly within a turn and only act on this one boundary signal. |
| `done`   | `{"message":"<final answer text>","refresh":bool,"navigate":string\|null}` | **Terminal.** `message` = the **final answer only** (post-last-tool text), i.e. exactly what the bubble holds after the reset rule above — so it's safe to use as the canonical text (e.g. for TTS, which should fire **once here**, not per-token). Then apply `refresh` / `navigate` exactly as with the legacy JSON response. Stream closes after this. |
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

## 6. Resolved / open items

- **Delta-append + TTS** — RESOLVED (Flutter #14): tokens are deltas (client concatenates);
  TTS fires once on `done.message` (the final answer), not per-token. No extra signal needed.
- **Intermediate-turn narration** — RESOLVED: handled by the `turn` reset rule (§3) — clients
  append blindly within a turn and clear on a `tool_use` turn boundary; `done.message` is the
  final answer only.
- **Session expiry** — RESOLVED: pre-stream HTTP `401`, never an SSE event (§2).
- Heartbeat interval may be tuned once we observe real edge/proxy timeouts.
