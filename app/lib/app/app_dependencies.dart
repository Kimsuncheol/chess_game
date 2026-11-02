import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../features/game/application/game_controller.dart';
import '../features/settings/application/settings_controller.dart';
import '../services/chess/chess_rules.dart';
import '../services/stockfish/chess_engine.dart';
import '../services/storage/local_storage.dart';
import '../services/unity/board_renderer.dart';

class AppDependencies {
  AppDependencies({
    required GameRepository games,
    required SettingsRepository preferences,
    required BoardRenderer renderer,
    required ChessRules rules,
    required ChessEngine engine,
  }) : settings = SettingsController(preferences),
       game = GameController(
         repository: games,
         renderer: renderer,
         rules: rules,
         engine: engine,
       ) {
    settings.addListener(_syncSettingsToGame);
  }

  factory AppDependencies.placeholder() {
    final storage = MemoryLocalStorage();
    return AppDependencies(
      games: storage,
      preferences: storage,
      renderer: PlaceholderUnityRenderer(),
      rules: const StandardChessRules(),
      engine: PlaceholderStockfishEngine(),
    );
  }

  factory AppDependencies.persistent(
    Directory directory, {
    BoardRenderer? renderer,
    ChessRules? rules,
    ChessEngine? engine,
  }) {
    final storage = FileLocalStorage(directory: directory);
    return AppDependencies(
      games: storage,
      preferences: storage,
      renderer: renderer ?? PlaceholderUnityRenderer(),
      rules: rules ?? const StandardChessRules(),
      engine: engine ?? PlaceholderStockfishEngine(),
    );
  }

  final SettingsController settings;
  final GameController game;

  void _syncSettingsToGame() {
    unawaited(game.applySettings(settings.settings));
  }

  Future<void> initialize() async {
    await Future.wait([settings.load(), game.load()]);
    await game.applySettings(settings.settings);
  }

  void dispose() {
    settings.removeListener(_syncSettingsToGame);
    settings.dispose();
    game.dispose();
    game.renderer.dispose();
    game.engine.dispose();
  }
}

/// Dependency lookup only; feature widgets subscribe to their own controllers.
class AppScope extends InheritedWidget {
  const AppScope({required this.dependencies, required super.child, super.key});
  final AppDependencies dependencies;
  static AppDependencies of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.dependencies;
  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
