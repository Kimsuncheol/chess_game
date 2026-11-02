# Local persistence and game history

Implemented 2026-11-02. Scope: offline, account-free local persistence for active and completed chess games, move lists, PGN exports, and app settings.

## Storage solution evaluation and decision

| Candidate | Maintenance / compatibility evidence | Characteristics | Decision |
| --- | --- | --- | --- |
| Dart SDK `dart:io` + `dart:convert` atomic file store (`FileLocalStorage`) paired with Android `Context.filesDir` (`MethodChannel('chess/storage/v1')`) | Maintained directly by the Dart and Flutter SDK teams as part of Dart 3.13.2 / Flutter 3.47.2. Zero third-party native `.so` binaries; natively compatible with Android API 36 and 16 KB page-size requirements. | Atomic write-to-temp-and-rename (`*.tmp` → `*.json`), serialized async write queue, deterministic replay validation via `ChessPosition.fromJson`, and direct testability on host filesystems without platform mocks. | **Selected** for durable local storage of games and settings. |
| `sqflite` / `drift` | Actively maintained Flutter SQLite plugins. | Relational indexing and multi-table SQL transactions, but introduces native Android/JNI dependencies that must be validated against the Unity IL2CPP / 16 KB page-size build matrix. | Deferred until multi-thousand-game relational queries are needed; repository interfaces (`GameRepository`, `SettingsRepository`) remain storage-agnostic. |
| `shared_preferences` | Actively maintained by the Flutter team. | Designed for small key-value flags rather than full move histories, PGN archives, and per-record corruption quarantine. | Not selected for game history storage. |
| Legacy `hive` (v2) | Original package is no longer actively maintained upstream. | Custom binary box format. | Rejected per maintenance requirement. |

## Persistence guarantees and schema

1. **No cloud, account, or telemetry dependencies:** All data lives in the app-private directory (`applicationContext.filesDir/still_chess_store` on Android) with `android:allowBackup="false"`. No Firebase, network calls, or user accounts are used.
2. **Saved after every completed move:** `GameController.start`, `attemptMove` (both human and AI turns), `selectPromotion`, `undo`, `claimDraw`, `restart`, and `resign` persist the updated `GameSession` through `GameRepository.saveGame` before publishing state to listeners or the renderer.
3. **Continue Game restoration:** Loading an unfinished `GameSession` replays all recorded UCI moves from `initialFen` through `ChessPosition.fromJson`, restoring the exact FEN position, SAN/UCI move history, repetition counts, draw-claim availability, player color, AI difficulty, and turn status.
4. **Completed game archive:** Completed sessions persist `id`, `startedAt`, `endedAt`, `date`, `result`, `termination`, concrete `playerColor`, `difficulty`, full `pgn` (Seven Tag Roster + SAN mainline), and the replay-verified `position`.
5. **Corruption and incomplete-data resilience:**
   - All writes serialize through an internal async lock and write to a temporary file (`games_v1.json.tmp` / `settings_v1.json.tmp`) with `flush: true` before renaming over the target file.
   - If a storage file is empty, truncated, or contains malformed top-level JSON, `FileLocalStorage` copies the offending file to `*.corrupt` for diagnostics, increments `corruptedRecordsSkipped`, and returns a safe empty list or default `AppSettings` without crashing.
   - Within `games_v1.json`, each game record is validated independently by `GameSession.fromJson` and `ChessPosition.fromJson` (checking schema version, rules version, legal move replay, FEN match, and result match). Corrupted or incomplete entries are skipped individually while preserving all valid saved games.

