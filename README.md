# Android 3D Chess

Flutter application shell: [app/README.md](app/README.md).

- [Architecture and implementation plan](docs/architecture.md)
- [Flutter–Unity JSON protocol](docs/unity_flutter_bridge.md)

Start the Android app:

```sh
cd app
flutter pub get
flutter run
```

The six-screen shell currently uses explicit placeholder integrations and session-only storage. Unity, legal chess moves, Stockfish, and durable storage are not connected yet.
