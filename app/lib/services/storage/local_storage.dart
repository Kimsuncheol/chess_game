import '../../features/game/domain/game_session.dart';
import '../../features/settings/domain/app_settings.dart';

abstract interface class GameRepository {
  Future<List<GameSession>> loadGames();

  /// The real SQLite implementation must atomically save moves and metadata.
  Future<void> saveGame(GameSession game);
}

abstract interface class SettingsRepository {
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
}

/// Session-only placeholder; intentionally does not claim durable persistence.
class MemoryLocalStorage implements GameRepository, SettingsRepository {
  final Map<String, GameSession> _games = {};
  AppSettings _settings = const AppSettings();

  @override
  Future<List<GameSession>> loadGames() async => List.unmodifiable(
    _games.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
  );
  @override
  Future<void> saveGame(GameSession game) async {
    _games[game.id] = game;
  }

  @override
  Future<AppSettings> loadSettings() async => _settings;
  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }
}
