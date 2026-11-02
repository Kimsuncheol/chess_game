# Authoritative Dart chess rules

Implemented 2026-11-02. Scope: untimed standard chess in Dart, independent of Flutter widgets, Unity and Stockfish. Rendering and engine integrations remain placeholders; this change does not enable the preview board to accept moves.

## Library evaluation and decision

The package registry, upstream source and licenses were checked before selection. Maintenance observations below are a point-in-time assessment, not a support guarantee.

| Candidate | Maintenance / compatibility evidence | License / standard-rules support | Decision |
| --- | --- | --- | --- |
| `bishop` 1.4.4 | Published 2024-07-14; upstream main has activity on 2026-10-30 (`711bfccec3ab65e8af5d900f0585722dbcc730aa`). Published SDK range is `>=3.2.0 <4.0.0`. | MIT; standard chess, legal generation, FEN, SAN and PGN. | Selected published release, pinned exactly; app owns draw adjudication. |
| `dartchess` 0.14.0 | Published 2026-09-29 by lichess.org; Dart `>=3.3.0 <4.0.0`; native platforms. | GPL-3.0; immutable positions, standard chess, FEN/SAN/PGN and insufficient material. | Technically suitable; avoid adding in-process GPL distribution obligations alongside the planned proprietary Unity runtime. |
| `chess` 0.8.1 | Published 2023-10-11; latest default-branch commit inspected is from 2023. Published SDK is `>=2.12.0 <3.0.0`, excluding this app's Dart 3.13.2. | MIT plus inherited BSD-2-Clause notices; standard legal moves, FEN/PGN. | Older maintenance and incompatible published SDK constraint; not selected. |

Primary evidence: [Bishop package](https://pub.dev/packages/bishop), [Bishop registry metadata](https://pub.dev/api/packages/bishop), [recent upstream commit](https://github.com/alexobviously/bishop/commit/711bfccec3ab65e8af5d900f0585722dbcc730aa), [dartchess package](https://pub.dev/packages/dartchess), [chess registry metadata](https://pub.dev/api/packages/chess), [chess license](https://pub.dev/packages/chess/license).

The exact Bishop 1.4.4 archive was inspected locally, including `LICENSE`, `pubspec.yaml`, standard variant configuration, move generation, FEN parsing, SAN output and game-ending code. Archive SHA-256 in `app/pubspec.lock`: `49739eff3ff06ec44f1660ff06baec6b44bb8926114b5f6bbed96f24d11a98d3`. Unreleased main currently has different Dart requirements, so no git dependency or unreleased code is used. No library files were patched.

The MIT notice is copied from the installed archive into `app/assets/licenses/BISHOP_LICENSE.txt` and registered with Flutter's license page. Retain it in redistribution. The selected release introduces no runtime package dependencies. [Published Bishop license](https://pub.dev/packages/bishop/license).

## Ownership and interfaces

`app/lib/features/game/domain/chess/chess_position.dart` contains the immutable aggregate `ChessPosition`. All constructors/transitions validate their inputs. Bishop objects are created privately for computations and never returned or retained as mutable public state. The domain files import no Flutter APIs or Unity/native services.

- `ChessPosition.initial()` creates standard chess; `fromFen(fen)` validates/imports a complete six-field FEN as a new game origin.
- `legalMoves(from: 'e2')` returns immutable move choices with UCI, capture, en passant and castling metadata. `legalDestinations('e2')` returns unique squares for highlights. `promotionChoices('e7', 'e8')` returns explicit legal promotion suffixes.
- `play('e2e4')` selects a move from Bishop's legal list before applying it and returns a new aggregate. Illegal moves, wrong-side pieces, moves leaving check, and moves after a result throw `ChessRuleException`.
- Promotion requires an explicit `q`, `r`, `b` or `n` suffix. Omitting it cannot silently choose a queen. Castling uses standard king destinations (`e1g1`, `e1c1`, `e8g8`, `e8c8`).
- `status` exposes turn, check/check-square, checkmate, stalemate, supported insufficient material, half-move clock, current repetition count, available draw claims, PGN result, and termination enum.
- `claimDraw(kind, intendedMove: ...)` validates a claim without applying the intended move. `undo(plies: ...)` rebuilds retained history and clears subsequent claims/results. `replayFens` includes the origin and every resulting position.
- `toJson/fromJson` store and replay the origin and UCI history, validating the cached final FEN and result. SAN, counters and repetition counts are regenerated, not trusted from storage. `toPgn` exports the recorded mainline.

`GameSession` surrounds this aggregate with ID, resolved player configuration, dates and a monotonic revision. Moves, undo, claims and resignation produce new session objects; undo never rewinds the revision. Session JSON also preserves metadata. `StandardChessRules` implements the existing service boundary and is installed by the application composition root. `PlaceholderChessRules` remains only as an explicitly unavailable test double.

`GameController.attemptMove` is the shared entry point for human and engine moves: it checks game ID, expected revision, actor color/turn and rules; cancels previous engine work; persists the new immutable session; then publishes it and asks the renderer to display it. Overlapping commands are rejected while busy. A failed write leaves both canonical and rendered state unchanged; a renderer failure after commit does not roll the game back. Late replies from before undo cannot apply because revisions differ. `claimDraw`, `undo`, `legalDestinations` and `exportPgn` are exposed through the controller as well.

The future Unity adapter must additionally enforce the attachment/session/message checks in [unity_flutter_bridge.md](unity_flutter_bridge.md). Game revision checks alone do not replace renderer session IDs or engine search-generation tokens.

## Supported draws and precedence

The implementation distinguishes claims from automatic results as described in FIDE Articles 9.2, 9.3 and 9.6. Checkmate takes precedence over the automatic 75-move result. The dead-position definition is broader than material counting; supported detection is explicitly limited below. [FIDE Laws of Chess](https://handbook.fide.com/chapter/e012023).

| Condition | Implemented behavior |
| --- | --- |
| Checkmate | Immediate win for the other side; no further moves |
| Stalemate | Immediate draw |
| Supported insufficient material | Immediate draw |
| Third/fourth occurrence of the same position | Claimable; play can continue without a claim |
| Fifth occurrence | Automatic draw |
| 100–149 consecutive half-moves without pawn movement/capture | Fifty-move draw can be claimed; play can continue |
| 150 half-moves | Automatic 75-move draw, unless the last move checkmates |
| Correct claim based on intended legal move | Draw at the current position; intended move is recorded as claim context, not as a played move |

Repetition identity includes placement, side to move, castling rights, and en passant **only when a legal capture exists**. Counters are excluded. A pinned pawn with an illegal en passant capture does not distinguish otherwise identical positions. Initial position counts once. Both current-position and intended-move claims are available. Claims are for the side to move; the controller checks whether the requesting human/engine represents that side.

The app does not use Bishop's aggregate `gameOver`/threefold/50-move defaults for adjudication. Its standard movement variant is configured with automatic thresholds 5/150; its material heuristic is disabled. The app independently counts repetitions and classifies results, including a square-color-aware material check.

Supported automatic material cases:

- King against king.
- One bishop or one knight against a bare king.
- Only kings and bishops remain, and **all** bishops occupy the same color complex, including promoted bishops.

Two knights against a king, bishops on opposite color complexes, and a knight/bishop against opposing blocking material are not automatically declared drawn merely because mate cannot be forced. This avoids confusing inability to force mate with inability to mate through any legal sequence.

## FEN, saved state and replay

The FEN validator requires eight valid ranks, exactly one king per side, standard piece/castling symbols, turn, valid counters, no unpromoted back-rank pawns, basic piece/promotion budgets, castling rights backed by matching home king/rook, and coherent en passant metadata. The side not to move may not be in check, which also rejects adjacent kings. Structural errors use `FormatException`.

FEN imports accept conventional en passant target fields even if no adjacent pawn can capture, but require the preceding double-pawn placement, empty origin/target and a zero half-move clock. Bishop serializes canonical FEN. FEN snapshots preserve castling, en passant and move counters, but cannot recover earlier repetitions or SAN history. Importing one therefore starts a fresh history. Resume an existing game using its full saved aggregate instead.

Saved position schema version 1 includes `rulesVersion: standard-v1-bishop-1.4.4`, origin FEN, ordered UCI moves, final FEN, result, termination and optional resignation/draw-claim context. Restore replays all legal moves, rejects moves after an automatic result, revalidates explicit claims/resignations, and compares the final position/result. Unsupported schema/rules versions are rejected rather than silently migrated. Session restore also validates concrete player color, dates, completion state and revision bounds.

The repository adapter is still in-memory. JSON codecs make the aggregate ready for a later SQLite implementation; they do not imply disk persistence exists. Current controller loading refuses corrupt state without overwriting it; selective quarantine and schema migrations belong to the future durable repository.

PGN export contains a single legal SAN mainline, Seven Tag Roster, the actual result token, escaped metadata, and protected `SetUp`/`FEN` tags for nonstandard origins. Black-to-move origins retain their correct move numbering. Result and setup tags cannot be overridden by caller metadata. Replay uses UCI history, while SAN carries disambiguation, capture, castling, promotion and check/mate suffixes.

## Explicit limitations

1. **No complete dead-position solver.** Locked pawn structures, fortresses and other dead arrangements outside the material classes above can remain active. Do not advertise complete FIDE dead-position adjudication. No tablebases or exhaustive reachability search are bundled.
2. **FEN validation is not retrograde proof.** Basic setup consistency is enforced; the validator does not prove that every accepted arrangement/counter/castling history is reachable from the orthodox initial position. Imported origins are trusted as the caller's chosen starting setup after these checks.
3. **Untimed application rules.** No chess clocks, flag fall, tournament arbiter procedures, touch-move penalties, draw agreements or event-specific rules. Resignation supports the normal loss and the obvious bare-opponent-king exception; complete one-sided mating-possibility analysis for all other resignation cases is not implemented.
4. **Standard chess only.** No Chess960, variants, null moves, premoves or automatic promotion defaults.
5. **PGN export/replay only.** No app-level PGN importer, branching variations, annotations or clock tags. Tests use Bishop's parser to check generated PGN; that parser is not exposed as a production import path.
6. **Integration remains staged.** Unity touch/highlight/promotion controls, Stockfish searches and UI draw-claim/export actions are not connected by this rules change. The game screen remains a clearly labeled noninteractive preview. The controller APIs are ready for those integrations.
7. **Baseline performance.** Immutable transitions reconstruct a private movement engine from the current FEN, and restore/undo replay history. Profile long games on physical Android devices before optimizing or introducing worker isolates. No mutable engine cache may become a second source of truth.

## Verification

`app/test/chess/chess_position_test.dart` covers known perft counts (initial depth 2: 400; Kiwipete depth 1: 48 and depth 2: 2039), legal turn/check handling, all four castlings, rights loss/corner-rook capture, en passant for both colors and pinned EP, promotions and underpromotions, mate/stalemate, supported material draws and false-positive exclusions, claimable/automatic draw thresholds, intended claims, counter resets, mate precedence, FEN validation, replay/restore/tamper rejection, PGN parsing and undo.

`app/test/chess/game_authority_test.dart` covers actor turns, stale revisions, overlapping commands, uncommitted/failed writes, renderer publication, restoration, undo invalidation of engine work and persistent claim context. Existing app navigation/setup/theme/accessibility tests continue to exercise the shell.
