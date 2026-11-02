import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/game/domain/game_session.dart';
import '../../features/settings/domain/app_settings.dart';

abstract interface class GameRepository {
  Future<List<GameSession>> loadGames();

  /// Atomically saves a game session (unfinished or completed) and its move history.
  Future<void> saveGame(GameSession game);
}

abstract interface class SettingsRepository {
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
}

/// In-memory repository used by isolated widget and unit tests.
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

/// Durable, offline local storage backed by atomic JSON files in the
/// application's private storage directory.
///
/// Uses write-to-temp-and-rename for crash safety and validates every saved
/// game by replaying its legal UCI move history from its initial FEN.
/// Corrupted or incomplete records are skipped and quarantined without crashing.
class FileLocalStorage implements GameRepository, SettingsRepository {
  FileLocalStorage({
    required this.directory,
    this.gamesFileName = 'games_v1.json',
    this.settingsFileName = 'settings_v1.json',
  });

  static const _channel = MethodChannel('chess/storage/v1');
  static const schemaVersion = 1;

  final Directory directory;
  final String gamesFileName;
  final String settingsFileName;

  Future<void> _lock = Future<void>.value();
  int _corruptedRecordsSkipped = 0;

  /// Number of corrupted or incomplete records skipped during load operations.
  int get corruptedRecordsSkipped => _corruptedRecordsSkipped;

  File get gamesFile => File('${directory.path}/$gamesFileName');
  File get settingsFile => File('${directory.path}/$settingsFileName');

  static Future<Directory> resolveDefaultDirectory() async {
    try {
      final path = await _channel.invokeMethod<String>('getStorageDirectory');
      if (path != null && path.isNotEmpty) {
        final dir = Directory('$path/still_chess_store');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return dir;
      }
    } catch (_) {
      // Fallback for desktop/test environments where the Android channel is absent.
    }
    final fallback = Directory('${Directory.systemTemp.path}/still_chess_store');
    if (!fallback.existsSync()) {
      fallback.createSync(recursive: true);
    }
    return fallback;
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
  }

  @override
  Future<List<GameSession>> loadGames() => _synchronized(_loadGamesUnlocked);

  @override
  Future<void> saveGame(GameSession game) => _synchronized(() async {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final existing = await _loadGamesUnlocked();
    final byId = <String, GameSession>{
      for (final item in existing) item.id: item,
      game.id: game,
    };
    final ordered = byId.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'updatedAt': DateTime.now().toIso8601String(),
      'games': ordered.map((g) => g.toJson()).toList(),
    };
    await _writeJsonAtomically(gamesFile, payload);
  });

  @override
  Future<AppSettings> loadSettings() => _synchronized(() async {
    final file = settingsFile;
    if (!file.existsSync()) return const AppSettings();
    try {
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return const AppSettings();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _corruptedRecordsSkipped++;
        await _quarantineFile(file);
        return const AppSettings();
      }
      final map = decoded.cast<String, Object?>();
      if (map['schemaVersion'] != null &&
          map['schemaVersion'] != schemaVersion) {
        _corruptedRecordsSkipped++;
        return const AppSettings();
      }
      return AppSettings.fromJson(map);
    } catch (_) {
      _corruptedRecordsSkipped++;
      await _quarantineFile(file);
      return const AppSettings();
    }
  });

  @override
  Future<void> saveSettings(AppSettings settings) => _synchronized(() async {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    await _writeJsonAtomically(settingsFile, settings.toJson());
  });

  Future<List<GameSession>> _loadGamesUnlocked() async {
    final file = gamesFile;
    if (!file.existsSync()) return const [];
    try {
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _corruptedRecordsSkipped++;
        await _quarantineFile(file);
        return const [];
      }
      final map = decoded.cast<String, Object?>();
      if (map['schemaVersion'] != schemaVersion || map['games'] is! List) {
        _corruptedRecordsSkipped++;
        await _quarantineFile(file);
        return const [];
      }
      final rawList = map['games'] as List;
      final restored = <GameSession>[];
      final seenIds = <String>{};
      for (final item in rawList) {
        if (item is! Map) {
          _corruptedRecordsSkipped++;
          continue;
        }
        try {
          final session = GameSession.fromJson(item.cast<String, Object?>());
          if (seenIds.add(session.id)) {
            restored.add(session);
          }
        } catch (_) {
          // Skip corrupted, incomplete, or rule-invalid game records without crashing.
          _corruptedRecordsSkipped++;
        }
      }
      restored.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return List.unmodifiable(restored);
    } catch (_) {
      _corruptedRecordsSkipped++;
      await _quarantineFile(file);
      return const [];
    }
  }

  Future<void> _writeJsonAtomically(
    File target,
    Map<String, Object?> data,
  ) async {
    final tempFile = File('${target.path}.tmp');
    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    tempFile.writeAsStringSync(encoded, flush: true);
    tempFile.renameSync(target.path);
  }

  Future<void> _quarantineFile(File file) async {
    try {
      if (file.existsSync()) {
        file.copySync('${file.path}.corrupt');
      }
    } catch (_) {}
  }
}
