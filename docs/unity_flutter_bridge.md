# Flutter–Unity chess bridge protocol

Status: proposed implementation contract, version **1**, dated 2026-11-01. This document is the normative wire contract for the bridge described in [architecture.md](architecture.md). It is transport-independent and does not select a Flutter–Unity plugin.

## 1. Authority and representation

Flutter owns rules, legal moves, turn order, promotion decisions, results, persistence, and the canonical position. Unity only renders Flutter commands and reports interaction intents. A Unity acknowledgment never commits a move. Flutter validates every intent against its current game, revision, input permissions, and legal moves before committing and persisting a transition.

**Version 1 uses full six-field FEN for board snapshots.** This supersedes the earlier architecture proposal to require a piece list. Unity parses FEN placement to create visuals; parsing is not chess adjudication. Side-to-move, castling, en-passant and counters are read-only metadata. Unity must not derive legal moves, special-move animations, check, or results from FEN. Flutter sends those explicitly. FEN does not replace Flutter's stored move/repetition history.

Squares match `^[a-h][1-8]$`, lowercase, independent of camera orientation. `a1` is dark. UCI moves match `^[a-h][1-8][a-h][1-8][qrbn]?$`. Piece codes in animation instructions use FEN letters (`P`, `N`, `B`, `R`, `Q`, `K`, and lowercase for black). Promotion choices use `q`, `r`, `b`, `n`. Standard chess only; Chess960 requires a later contract.

## 2. Encoding and envelope

One bridge call carries one UTF-8 JSON object, maximum 64 KiB encoded. No concatenated objects, binary payloads, executable strings, or per-frame updates. Both receivers serialize handling on their application/scene thread; native transport IO must not block that thread.

| Field | Type | Contract |
| --- | --- | --- |
| `protocolVersion` | integer | Required; exactly `1`. Unsupported versions produce `error` and disable interaction. No silent downgrade. |
| `type` | string | Required; one of the types below, case-sensitive. |
| `messageId` | string | Required; sender-generated UUID in production, globally unique for each logical message. Examples use short readable IDs. Retry the identical message with the same ID. |
| `sessionId` | string | Required; Flutter-generated attachment token, bound by the host before Unity sends readiness. |
| `gameId` | string or null | Required; null only for readiness and errors before a game is bound. |
| `revision` | integer or null | Required; nonnegative Dart game revision, null only with null `gameId`. Not a ply number; undo/load also advances it. |
| `sequence` | integer | Required; per-sender monotonically increasing integer within the session, starting at 1. Retries preserve it. |
| `replyTo` | string or null | Required; triggering `messageId`, otherwise null. |
| `payload` | object | Required; type-specific fields. |

Integers must be at most `9007199254740991`. IDs are nonempty strings of at most 128 characters. Do not order UUIDs or use wall-clock time to decide freshness. Receivers ignore unknown additional fields, reject missing/invalid required fields and unknown enum values, and respond to unknown types with `UNSUPPORTED_TYPE`. Incompatible field/meaning changes require a new protocol version; optional additive fields may remain in v1. Duplicate JSON keys are invalid.

## 3. Attachment, readiness, and complete resynchronization

The native/adapter host binds a fresh `sessionId` to each Unity attachment **before normal messages**, using an initialization parameter or dedicated bootstrap call. Unity clears its board, sequence/deduplication state and input, creates a fresh `rendererInstanceId`, then emits `unity.ready`. The host delivers callbacks only from its active attachment; a delayed readiness event from a destroyed instance must not rebind the current renderer. This bootstrap requirement is part of the adapter contract, not a plugin-specific API claim.

1. Flutter attaches its event listener and provisions the session. Unity is `awaitingSnapshot`, with touch disabled.
2. Unity sends `unity.ready` with supported versions and instance ID. Until a snapshot is acknowledged, it retries the **same** readiness message every 1 second, up to 5 times. Flutter can retry attachment if none arrives within 5 seconds.
3. Flutter checks the active attachment/session, selects v1, and sends `board.snapshot` for its latest committed state. It includes **all** display state: FEN, selection/highlights, status, promotion context, camera and input permissions. It uses `replyTo` for the readiness ID and targets the instance ID in its payload.
4. Unity constructs the entire replacement board off-screen, validates the snapshot's shape, and swaps it atomically. It cancels all old visual work, then returns `bridge.ack` with `outcome: "applied"`. Only then may Flutter enable interaction through a newer complete snapshot or current-revision display command. The first snapshot should normally set `inputEnabled: true` only when Dart permits human input; Unity still waits until its local application completes.
5. If Unity reloads, loses its scene, or the host reattaches, repeat with a **new session**, even for the same game/revision. Flutter resends its latest full snapshot, never pending animation deltas or a move history for Unity to replay.

Duplicate `unity.ready` in an already synchronized session must not clear the board or restart animations. Flutter retries its bootstrap snapshot if its acknowledgment is missing. If already acknowledged, it may resend the cached acknowledgment path by retransmitting the same snapshot; deduplication makes this harmless. Retire the old session on a game switch or renderer loss, and bootstrap a new one. An old game's snapshot therefore cannot switch the current board back.

**Before readiness:** Flutter retains only the latest canonical desired snapshot in memory. It coalesces status/highlights/camera preferences into that snapshot and discards animation requests; it does not send ordinary game commands. Unity receiving a command before emitting readiness or before the initial snapshot rejects it with `NOT_READY`, except that the first valid `board.snapshot` is accepted after readiness. Unity never queues gameplay intents across readiness. Initial scene setup and duplicate readiness retries do not authorize input.

**Resync without reload:** either endpoint may request `bridge.resyncRequest`; Flutter immediately disables interaction locally and sends a newer-sequence complete `board.snapshot`, including at the same revision. Unity does not roll back the authoritative revision. An acknowledgment timeout (2 seconds for snapshots; animation duration plus 2 seconds for animations) triggers this path; retry a snapshot at most twice before showing a recoverable connection error and offering reattachment. Pause timeout clocks while the app is suspended and resync on resume.

## 4. Freshness, idempotency, and animation safety

Unity tracks `acceptedRevision`, `appliedRevision`, the last successfully applied Flutter sequence, and an active animation generation. During animation, the accepted target revision may exceed the fully applied visual revision. Unity disables board interaction until the target is applied. Flutter tracks its own canonical revision and never takes it from Unity.

Process incoming commands in this order:

1. Validate envelope, direction, active session and bound game (initial snapshot binds the game), then payload. Wrong-session/game messages have no effects and no replies on the new session.
2. Look up `messageId`. Identical duplicate: return the cached response or current `inProgress` acknowledgment without repeating any effects. Reusing an ID with changed content produces `ID_CONFLICT`. A retry must be byte-identical. Maintain a bounded cache of the latest 512 messages per sender/session; the sequence/revision rules below also protect after eviction.
3. For Flutter commands, `sequence <= lastAppliedFlutterSequence` is stale and cannot apply. A larger sequence may skip gaps; gaps do not cause waiting. Advance the watermark only after accepting a valid command. A snapshot can always repair a skipped display update.
4. A `board.snapshot` must have `revision >= acceptedRevision`; equal-revision snapshots are allowed with newer sequence to reset visuals. A `move.animate` must have `baseRevision == appliedRevision == acceptedRevision`, no active animation, and target envelope `revision == baseRevision + 1`. Reject stale targets; request resync on a forward gap/base mismatch. Commands cannot use a higher sequence to override revision checks.
5. `legalMoves.highlight`, `promotion.request`, `camera.reset`, and `game.status` require envelope `revision == acceptedRevision`. Highlights/promotion additionally require an idle, fully applied board. An out-of-order future revision is rejected with `REVISION_MISMATCH` and requests resync, not buffered.
6. On accepting animation, immediately reserve its `animationId` and target revision, advance the sequence watermark, and increment generation. Duplicate animation ID for the same game/session is never replayed, even with a different message ID. A target at or below `acceptedRevision` also cannot replay. A conflicting reuse is an error.
7. Any newer accepted snapshot cancels the active tween and invalidates its callbacks through generation checks. Old tween completions must not reposition pieces, remove captures, send a successful completion, or enable input. Camera/status updates do not cancel an otherwise current animation.

Keep the latest 512 animation IDs; revisions protect older evicted entries. A duplicate still running returns `inProgress`; a completed duplicate returns its cached terminal acknowledgment. Rejected messages may receive an acknowledgment with `outcome: "ignored"` and a reason, but may never alter the board. `bridge.ack` and `error` do not advance Flutter command ordering and are never themselves acknowledged.

Flutter deduplicates Unity intents by ID, rejects out-of-order interaction sequences using a separate accepted-intent watermark, and requires `revision == canonicalRevision`. An intent is accepted at most once. Highlight and promotion request IDs add context when the board revision alone cannot distinguish two selections. Duplicate physical input sent with a new ID still has to satisfy the active turn, current selection/request, and command queue checks. Old acknowledgment/error events never change canonical state or re-enable controls.

## 5. Message catalog

### `unity.ready` — Unity → Flutter

Payload: `rendererInstanceId: string`, `supportedProtocolVersions: integer[]` (must include 1), `capabilities: string[]` (v1 requires `fenSnapshot`, `explicitAnimation`). Envelope game/revision are null. Envelope version is the bootstrap version 1. No compatibility intersection means show an integration error; do not send game data.

```json
{
  "protocolVersion": 1,
  "type": "unity.ready",
  "messageId": "u-ready-1",
  "sessionId": "session-A",
  "gameId": null,
  "revision": null,
  "sequence": 1,
  "replyTo": null,
  "payload": {
    "rendererInstanceId": "renderer-A",
    "supportedProtocolVersions": [1],
    "capabilities": ["fenSnapshot", "explicitAnimation"]
  }
}
```

### `board.snapshot` — Flutter → Unity

Payload: `rendererInstanceId`, `fen`, `selectedSquare` (square or null), `highlights` (highlight object below or null), `status` (status object below), `pendingPromotion` (promotion request object below or null), `camera` (`orientation: white|black`, `preset: default`), `inputEnabled` (boolean). All fields are required; null clears prior transient state. Snapshot always snaps without animation and must not reuse previous scene pieces as authoritative state.

Validate FEN structurally: exactly six fields; eight ranks each expanding to eight squares; known placement letters, `w|b`, valid standard castling/en-passant tokens, nonnegative halfmove and positive fullmove. Flutter ensures chess legality; Unity rejects malformed data without partially clearing its existing scene. A promotion result is already represented as its new piece in FEN. Local visual object IDs may be rebuilt after any snapshot.

```json
{
  "protocolVersion": 1,
  "type": "board.snapshot",
  "messageId": "f-snapshot-1",
  "sessionId": "session-A",
  "gameId": "game-1",
  "revision": 0,
  "sequence": 1,
  "replyTo": "u-ready-1",
  "payload": {
    "rendererInstanceId": "renderer-A",
    "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "selectedSquare": null,
    "highlights": null,
    "status": {
      "phase": "humanTurn", "sideToMove": "white", "checkSquare": null,
      "result": "*", "termination": null, "canClaimDraw": false
    },
    "pendingPromotion": null,
    "camera": {"orientation": "white", "preset": "default"},
    "inputEnabled": true
  }
}
```

### `player.squareSelected` — Unity → Flutter

Payload: `square`, `interaction: tap|dragStart|dragEnd`, `selectionRequestId` (last highlight command's message ID, or null). Envelope revision is Unity's fully applied revision. Unity emits only while input is enabled and idle. A second tap/drag end reports a destination square; Flutter decides its meaning and legal consequences. Dragging moves only a ghost preview, never the committed piece. Flutter clears the ghost with its next display command/snapshot.

```json
{
  "protocolVersion": 1,
  "type": "player.squareSelected",
  "messageId": "u-select-1",
  "sessionId": "session-A",
  "gameId": "game-1",
  "revision": 0,
  "sequence": 3,
  "replyTo": null,
  "payload": {"square": "e2", "interaction": "tap", "selectionRequestId": null}
}
```

### `legalMoves.highlight` — Flutter → Unity

Payload is a highlight object: `selectedSquare` (square or null), `moves` (array of `{to: square, style: quiet|capture, promotionChoices: array of q|r|b|n}`), `inputEnabled` (boolean). One entry per destination; a nonpromotion has empty choices. Empty moves/null selection clears highlights. For this message, its `messageId` is the selection request ID. In a snapshot, add `selectionRequestId` to the nonnull highlight object because it is embedded rather than a separate command. Flutter validates destination events against that ID; Unity uses it only for correlation and visuals. It does not treat these hints as permission to commit a move.

```json
{
  "protocolVersion": 1,
  "type": "legalMoves.highlight",
  "messageId": "f-highlight-1",
  "sessionId": "session-A",
  "gameId": "game-1",
  "revision": 0,
  "sequence": 2,
  "replyTo": "u-select-1",
  "payload": {
    "selectedSquare": "e2",
    "moves": [
      {"to": "e3", "style": "quiet", "promotionChoices": []},
      {"to": "e4", "style": "quiet", "promotionChoices": []}
    ],
    "inputEnabled": true
  }
}
```

The corresponding destination event has `square: "e4"`, `interaction: "tap"`, `selectionRequestId: "f-highlight-1"`, the same revision, and a fresh Unity message ID/sequence.

### `move.animate` — Flutter → Unity

Sent **after** Dart commits/persists a legal move. Payload fields:

| Field | Meaning |
| --- | --- |
| `animationId` | Unique ID for this committed transition; unchanged across retries |
| `baseRevision`, `beforeFen` | Exact expected current visual position; Unity requires matching FEN as well as revision |
| `uci`, `kind` | Display metadata; kind is `normal`, `capture`, `castle`, `enPassant`, `promotion`, or `promotionCapture` |
| `durationMs` | Integer 0–2000; 0 for reduced motion |
| `relocations` | Array of `{from, to, piece}`; source squares address visuals in the base FEN |
| `captures` | Array of `{square, piece}`; explicit removals, never inferred from destination |
| `promotion` | Null or `{square, fromPiece, toPiece}` applied at arrival |
| `target` | **Complete snapshot payload** (including `fen`) for the committed target revision |

All fields are required. Apply all relocations/removals as one visual transition: source lookup is against the base layout, not an incrementally mutated board. Remove/fade captures at the transition start, move the relocations concurrently, then replace a promoted pawn at arrival. Temporary visuals cannot accept input. At completion, atomically reconcile to `target`, set `appliedRevision = acceptedRevision`, clear highlights/ghosts as specified, and acknowledge. If reconciliation/animation fails, keep input disabled and request a snapshot. Do not advance Flutter's canonical state from completion.

The following is a complete ordinary `e2e4` example following the starting snapshot:

```json
{
  "protocolVersion": 1,
  "type": "move.animate",
  "messageId": "f-animate-1",
  "sessionId": "session-A",
  "gameId": "game-1",
  "revision": 1,
  "sequence": 3,
  "replyTo": "u-destination-1",
  "payload": {
    "animationId": "game-1-transition-1",
    "baseRevision": 0,
    "beforeFen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "uci": "e2e4", "kind": "normal", "durationMs": 250,
    "relocations": [{"from": "e2", "to": "e4", "piece": "P"}],
    "captures": [], "promotion": null,
    "target": {
      "rendererInstanceId": "renderer-A",
      "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
      "selectedSquare": null, "highlights": null, "pendingPromotion": null,
      "status": {
        "phase": "aiThinking", "sideToMove": "black", "checkSquare": null,
        "result": "*", "termination": null, "canClaimDraw": false
      },
      "camera": {"orientation": "white", "preset": "default"},
      "inputEnabled": false
    }
  }
}
```

#### Special move animation instructions

These JSON fragments illustrate the relevant **payload fields**, not complete standalone messages; each must also have base/target FEN, revisions, animation ID and all other fields above. Flutter supplies the complete post-move snapshot in every case.

- **Castling:** animate king and rook concurrently. Never infer rook movement from a two-square king move. For white kingside:

```json
{
  "uci": "e1g1", "kind": "castle",
  "relocations": [
    {"from": "e1", "to": "g1", "piece": "K"},
    {"from": "h1", "to": "f1", "piece": "R"}
  ],
  "captures": [], "promotion": null
}
```

White queenside explicitly uses `e1→c1`, `a1→d1`; black kingside `e8→g8`, `h8→f8`; black queenside `e8→c8`, `a8→d8`. Legality is checked only by Flutter.

- **En passant:** explicitly remove the pawn from its actual square, not the landing square:

```json
{
  "uci": "e5d6", "kind": "enPassant",
  "relocations": [{"from": "e5", "to": "d6", "piece": "P"}],
  "captures": [{"square": "d5", "piece": "p"}], "promotion": null
}
```

- **Promotion:** move the pawn, then replace its mesh with the exact Flutter-chosen piece. Underpromotions use the same path. A capture-promotion also lists the captured piece:

```json
{
  "uci": "g7h8n", "kind": "promotionCapture",
  "relocations": [{"from": "g7", "to": "h8", "piece": "P"}],
  "captures": [{"square": "h8", "piece": "r"}],
  "promotion": {"square": "h8", "fromPiece": "P", "toPiece": "N"}
}
```

A noncapture `e7e8q` uses `kind: "promotion"`, empty captures and `toPiece: "Q"`. Black promotions use lowercase FEN letters. Unity checks that referenced visuals exist and targets are structurally consistent, but does not validate chess rules; conflicting instructions produce `INVALID_ANIMATION` and resync.

### `promotion.request` — Flutter → Unity

Payload: `promotionRequestId`, `from`, `to`, `color: white|black`, `choices` (distinct nonempty subset of `q,r,b,n`), `presentation: flutter|unity`. Flutter creates the ID and keeps the board at the **pre-move revision** until selection is validated. A new request replaces the old one; snapshots with null pending promotion clear it. While pending, board interaction is disabled; only the requested picker can emit a choice. Cancellation/undo invalidates the request in Flutter and sends a complete snapshot.

Normally Flutter displays its own accessible picker (`presentation: "flutter"`); Unity only shows the pending visual state, and no Unity selection event is necessary. `presentation: "unity"` supports the full-screen renderer fallback. Unity may display the supplied choices but never auto-select, default to queen, or commit a pawn move.

This independent example uses a separate session/game and is not a continuation of `e2e4` above:

```json
{
  "protocolVersion": 1,
  "type": "promotion.request",
  "messageId": "f-promotion-1",
  "sessionId": "session-P",
  "gameId": "game-P",
  "revision": 18,
  "sequence": 8,
  "replyTo": "u-pawn-destination-1",
  "payload": {
    "promotionRequestId": "promotion-P-18",
    "from": "e7", "to": "e8", "color": "white",
    "choices": ["q", "r", "b", "n"], "presentation": "unity"
  }
}
```

### `promotion.selected` — Unity → Flutter

Payload: `promotionRequestId`, `choice`. Flutter requires current revision/session/game, an active matching request, matching presentation, and a choice in the allowed set. It then revalidates the complete promotion move, persists it, and sends `move.animate` or a snapshot. A canceled/replaced/already-consumed request cannot change the game.

```json
{
  "protocolVersion": 1,
  "type": "promotion.selected",
  "messageId": "u-promotion-choice-1",
  "sessionId": "session-P",
  "gameId": "game-P",
  "revision": 18,
  "sequence": 12,
  "replyTo": "f-promotion-1",
  "payload": {"promotionRequestId": "promotion-P-18", "choice": "n"}
}
```

In a snapshot, `pendingPromotion` contains the full request payload plus `requestMessageId`, used as `replyTo` for a Unity choice after resync. Flutter reissues a fresh request ID when restoring a pending interaction into a new attachment session.

### `camera.reset` — Flutter → Unity

Payload: `orientation: white|black`, `preset: default`, `durationMs: 0..2000`. The preset uses Unity-authored bounded camera coordinates; do not send arbitrary scene code. Reset orbit/pan/zoom to that view, leaving FEN/highlights/game revision untouched. A new reset cancels an older camera tween; session/generation guards suppress late callbacks. Gesture camera movement otherwise stays local.

```json
{
  "protocolVersion": 1,
  "type": "camera.reset",
  "messageId": "f-camera-1",
  "sessionId": "session-A",
  "gameId": "game-1",
  "revision": 1,
  "sequence": 4,
  "replyTo": null,
  "payload": {"orientation": "black", "preset": "default", "durationMs": 300}
}
```

### `game.status` — Flutter → Unity

Payload: `status` and `inputEnabled`. The status object is required in snapshots as well:

- `phase`: `humanTurn`, `promotionPending`, `aiThinking`, `paused`, `finished`, or `recoverableError`.
- `sideToMove`: `white|black`; `checkSquare`: square or null, supplied by Flutter.
- `result`: `*`, `1-0`, `0-1`, or `1/2-1/2`.
- `termination`: null for an active game, otherwise `checkmate`, `stalemate`, `deadPosition`, `resignation`, `threefoldClaim`, `fiftyMoveClaim`, `fivefoldRepetition`, `seventyFiveMove`, or `agreement`.
- `canClaimDraw`: boolean, for display only.

Unity never infers finished/check state from FEN. Input requires a fully synchronized idle board, `inputEnabled: true`, and `phase: humanTurn`; promotion choice has its separate permission. A status received during animation updates status/permissions immediately, and its newer values must be retained when animation target reconciliation completes. The same applies to a newer camera reset: target reconciliation cannot overwrite newer display settings. Track per-display-field command sequence to merge correctly, or defer status/camera commands until animation finishes in Flutter.

```json
{
  "protocolVersion": 1,
  "type": "game.status",
  "messageId": "f-status-1",
  "sessionId": "session-A",
  "gameId": "game-1",
  "revision": 1,
  "sequence": 5,
  "replyTo": null,
  "payload": {
    "status": {
      "phase": "paused", "sideToMove": "black", "checkSquare": null,
      "result": "*", "termination": null, "canClaimDraw": false
    },
    "inputEnabled": false
  }
}
```

### `bridge.ack` — either direction

Payload: `outcome: applied|inProgress|ignored`, `reason` (null or a defined error code), `animationId` (string or null). `replyTo` is required and nonnull. Echo the acknowledged command's game/revision; it describes that command, not necessarily the newest displayed revision. Flutter may acknowledge accepted interaction receipt with `applied`; this means controller processing, not proof that a move occurred. The subsequent Flutter command conveys the authoritative outcome. Unity's terminal animation acknowledgment is emitted only after reconciliation.

```json
{
  "protocolVersion": 1,
  "type": "bridge.ack",
  "messageId": "u-ack-animation-1",
  "sessionId": "session-A",
  "gameId": "game-1",
  "revision": 1,
  "sequence": 6,
  "replyTo": "f-animate-1",
  "payload": {"outcome": "applied", "reason": null, "animationId": "game-1-transition-1"}
}
```

### `bridge.resyncRequest` — either direction

Payload: `reason` (error code), `appliedRevision` (integer or null), `acceptedRevision` (integer or null). Unity reports its visual revisions; Flutter requesting resync does not trust these as canonical. Flutter's action is always a newer-sequence snapshot of its own latest committed state. Unity must not send a FEN to overwrite Dart state. A request received while attaching is coalesced into the initial snapshot.

### `error` — either direction

Payload: `code`, `message` (developer-safe text, maximum 512 characters), `recoverable` (boolean), `action: none|resync|reattach|upgrade`. Correlate with `replyTo` when an offending message ID is available. Use null game/revision only before binding. Unsupported version responses use envelope version 1. If the envelope cannot be parsed safely, log/drop it locally without reflecting its contents. Do not answer an error with another error, and rate-limit repeated diagnostics.

| Code | Required behavior |
| --- | --- |
| `NOT_READY` | No application; Flutter waits for readiness or resends initial snapshot |
| `UNSUPPORTED_VERSION`, `UNSUPPORTED_TYPE` | No application; unsupported version disables interaction and requires upgrade; unknown type reports unsupported operation |
| `INVALID_MESSAGE`, `INVALID_FEN`, `INVALID_ANIMATION`, `ID_CONFLICT` | No partial changes; repair with snapshot when recoverable |
| `STALE_MESSAGE`, `REVISION_MISMATCH` | Ignore stale state; request snapshot for forward gaps/mismatch |
| `STALE_SELECTION`, `INVALID_PROMOTION`, `INPUT_DISABLED` | Flutter ignores intent; returns current highlights/status/snapshot as appropriate |
| `RENDER_FAILURE`, `ACK_TIMEOUT` | Disable interaction, resync; reattach after bounded recovery fails |

Errors are diagnostic events only. They cannot change a position, result, or current selection in Flutter. Recovery is a separate controller decision.

```json
{
  "protocolVersion": 1,
  "type": "error",
  "messageId": "u-error-1",
  "sessionId": "session-A",
  "gameId": "game-1",
  "revision": 1,
  "sequence": 7,
  "replyTo": "f-bad-animation-1",
  "payload": {
    "code": "REVISION_MISMATCH",
    "message": "Animation base does not match the displayed revision.",
    "recoverable": true,
    "action": "resync"
  }
}
```

## 6. Implementation acceptance cases

Before integrating real gameplay, exercise this contract with fake transports in Dart and Unity:

1. Delayed readiness sends only the latest snapshot; intermediate moves never replay on attachment.
2. Unity reload during an animation creates a new session; the old animation callback and ready/ack messages cannot touch the new board.
3. An identical animation retry, a new message ID with the same animation ID, and a stale target revision all fail to replay the move.
4. A newer snapshot interrupts a tween; its late completion cannot remove/reposition pieces or enable input.
5. Reordered highlights/status, a forward animation gap, old-game snapshots and stale selection IDs produce no unauthorized board change.
6. All four castlings, en passant for both colors, all promotions and capture-promotions reconcile exactly to target FEN with reduced motion on/off.
7. A duplicate/stale promotion choice cannot commit twice, including after undo, request replacement, or reload.
8. Invalid FEN/JSON/version/type and oversized messages cause no partial scene updates or error loops.
9. Lost acknowledgment triggers bounded snapshot recovery; Flutter remains authoritative throughout.
10. Camera/status changes during animation survive target reconciliation without modifying the board position.

These are implementation acceptance criteria; this documentation change does not claim runtime bridge tests have passed.
