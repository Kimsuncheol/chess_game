# Android 3D Chess

Flutter application shell: [app/README.md](app/README.md).

- [Architecture and implementation plan](docs/architecture.md)
- [Authoritative Dart chess rules](docs/chess_rules.md)
- [Local persistence and game history](docs/local_persistence.md)
- [Flutter–Unity JSON protocol](docs/unity_flutter_bridge.md)
- [Dart chess rules, library selection and limitations](docs/chess_rules.md)

Start the Android app:

```sh
cd app
flutter pub get
flutter run
```

The six-screen shell currently uses explicit placeholder integrations and session-only storage. Authoritative Dart rules, move history and PGN export are implemented. Unity, Stockfish and durable storage are not connected yet.
