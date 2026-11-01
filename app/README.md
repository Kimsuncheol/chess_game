# Still Chess — Flutter application

An Android-first Flutter shell for the offline 3D chess architecture. The interface uses Material 3, neutral colors, responsive cards, and system/light/dark appearance. This milestone supplies app navigation and session orchestration; it does not implement playable chess.

## Run

Requires Flutter 3.47.2 stable / Dart 3.13.2 (the SDK used for this scaffold), an Android SDK, and a connected Android device or emulator. Dependencies are locked in `pubspec.lock`.

```sh
cd app
flutter pub get
flutter run
```

From the `app` directory:

```sh
flutter analyze
flutter test
flutter build apk --debug
```

The app targets Android API 36, supports API 26+, and imposes no orientation lock. Only Android platform files are generated. Use the Android Studio JDK/toolchain compatible with the generated Gradle/AGP versions. Release signing is intentionally unconfigured: supply an upload key outside source control before building a distributable release. The application ID must be reserved/reviewed before Google Play publication.

## Feature organization

```text
lib/
  app/                 Composition root, dependency scope, router, theme
  core/widgets/        Shared accessible page and feedback widgets
  features/
    home/presentation/
    game_setup/presentation/
    game/
      domain/          Immutable configuration/session; no Flutter imports
      application/     GameController, session writes and result orchestration
      presentation/    Game screen and noninteractive preview
    game_result/presentation/
    history/presentation/
    settings/
      domain/          Immutable preferences and appearance enum
      application/     SettingsController
      presentation/
  services/
    unity/             BoardRenderer contract and placeholder
    chess/             ChessRules contract and fail-closed placeholder
    stockfish/         ChessEngine contract and unavailable placeholder
    storage/           Game/SettingsRepository contracts and memory adapter
```

## State management decision

Feature-scoped `ChangeNotifier` controllers expose immutable state through getters. Widgets subscribe using `ListenableBuilder`; `AppScope` only resolves dependencies. `AppDependencies` is the composition root and supports injecting test doubles and later production adapters. The app owns/disposes its controllers, router and services.

This approach fits the small offline shell: it uses Flutter's observable APIs, keeps side effects out of screens, avoids code generation, and makes failure/concurrency behavior directly testable. Separate settings and game controllers prevent unrelated game notifications from rebuilding the app theme. A controller's asynchronous commands publish state only after repository writes succeed and guard overlapping writes/disposal. A future rules/AI implementation must add the full serialized move queue and session/revision checks specified by the architecture; these placeholders do not claim to implement that gameplay pipeline. [Flutter ChangeNotifier documentation](https://api.flutter.dev/flutter/foundation/ChangeNotifier-class.html).

`go_router` is used for Router-based navigation and Android Back behavior; route construction is centralized in `app/app_router.dart`. Screen arguments use path parameters rather than unsafe object casts. Missing session IDs and unknown paths display recovery screens. [go_router documentation](https://pub.dev/packages/go_router).

| Screen | Route |
| --- | --- |
| Home | `/` |
| Game Setup | `/setup` |
| Game | `/game/:gameId` |
| Game Result | `/game/:gameId/result` |
| History | `/history` |
| Settings | `/settings` |

Setup replaces its route with the board; ending a session navigates to its result. The result page cannot invent a finished result for an open session. Back navigation keeps the session in memory. Resignation requires confirmation.

## Current service behavior

- **Unity:** no plugin selected or native Unity runtime included. `PlaceholderUnityRenderer` holds a supplied Flutter snapshot but remains unavailable. The visible 2D starting-board illustration is decorative, labeled as a preview, and accepts no moves. Camera control is disabled until a renderer is available.
- **Rules:** no legal moves returned; applying a move throws `UnsupportedError`. No unvalidated move can enter the game state.
- **Stockfish:** no engine binary or JNI library included. Searches fail explicitly; no fabricated AI response. Cancel/dispose are safe lifecycle placeholders.
- **Local storage:** an injected in-memory repository backs the current session's preferences and history. All data resets on process exit. This is deliberately not durable SQLite storage yet. Android cloud/device backup is excluded.

Creating a session, choosing a side/difficulty, returning home, resuming, resigning, viewing results/history, changing appearance and selecting experience preferences work within the current app process. Random side resolves when the session is created. Sound is a stored preference only. Reduced motion combines the preference with device accessibility flags.

There is no Firebase, authentication, analytics, multiplayer or remote engine service. The release manifest has no Internet permission; debug/profile manifests retain Flutter development tooling permissions.

## Responsive and accessible UI

Content has a bounded reading width. Wide layouts place the board beside text; compact windows and large text use a single scrollable column. No fixed-height content panels or orientation constraints clip growing text. Theme-aware colors, semantic headings/feedback, labeled icon controls, standard radio/switch semantics and minimum 48 dp controls support accessibility. Only the decorative board glyphs opt out of text scaling and are replaced by one descriptive semantic label. Functional content honors device text scaling. Real TalkBack, device contrast and Unity accessibility still require physical-device testing.

## Verification and remaining integration work

Tests cover navigation through setup/game/result/history, invalid routes, system and explicit appearance changes across navigation, 320 dp screens at 200% text, wide layout, Android touch-target/label/contrast guidelines, concurrent creation, failed writes, fail-closed rules, settings save failure and result persistence into the injected repository.

Follow [the architecture](../docs/architecture.md) and [bridge contract](../docs/unity_flutter_bridge.md) when replacing placeholders. The Flutter/Unity compatibility spike, real Dart rules, Stockfish packaging, SQLite migrations, real-device performance and Google Play/license gates remain outstanding. Do not treat this shell or its debug APK as a production-ready game.
