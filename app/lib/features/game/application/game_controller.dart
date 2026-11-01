import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../services/chess/chess_rules.dart';
import '../../../services/stockfish/chess_engine.dart';
import '../../../services/storage/local_storage.dart';
import '../../../services/unity/board_renderer.dart';
import '../domain/game_session.dart';

/// Canonical session orchestration. Widgets never write to native services.
class GameController extends ChangeNotifier {
  GameController({
    required this._repository,
    required this.rules,
    required this.engine,
    required this.renderer,
  });
  final GameRepository _repository;
  final ChessRules rules;
  final ChessEngine engine;
  final BoardRenderer renderer;
  List<GameSession> _games = const [];
  String? _activeId;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  int _nextId = 0;
  List<GameSession> get games => List.unmodifiable(_games);
  GameSession? get activeGame => find(_activeId);
  bool get busy => _busy;
  String? get error => _error;
  bool get canPlay =>
      rules.isAvailable && engine.isAvailable && renderer.isAvailable;

  GameSession? find(String? id) {
    for (final game in _games) {
      if (game.id == id) return game;
    }
    return null;
  }

  Future<void> load() async {
    _games = await _repository.loadGames();
    for (final game in _games) {
      if (!game.isFinished) {
        _activeId = game.id;
        break;
      }
    }
  }

  Future<GameSession?> start(GameConfiguration configuration) async {
    if (_busy || _disposed) return null;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final color = configuration.color == PlayerColor.random
          ? (Random().nextBool() ? PlayerColor.white : PlayerColor.black)
          : configuration.color;
      final now = DateTime.now();
      final game = GameSession(
        id: '${now.microsecondsSinceEpoch}-${_nextId++}',
        configuration: GameConfiguration(
          color: color,
          difficulty: configuration.difficulty,
        ),
        startedAt: now,
      );
      await _repository.saveGame(game);
      if (_disposed) return null;
      _games = [game, ..._games];
      _activeId = game.id;
      // A renderer failure must not undo a successfully persisted session.
      try {
        await renderer.render(game);
      } catch (_) {
        _error =
            'The board could not be opened. Your session is still available.';
      }
      return _disposed ? null : game;
    } catch (_) {
      _error = 'The session could not be created. Please try again.';
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<GameSession?> resign(String id) async {
    final current = find(id);
    if (_busy || _disposed || current == null || current.isFinished) {
      return null;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await engine.cancel();
      final finished = current.resign(DateTime.now());
      await _repository.saveGame(finished);
      if (_disposed) return null;
      _games = [
        for (final game in _games)
          if (game.id == id) finished else game,
      ];
      if (_activeId == id) _activeId = null;
      return finished;
    } catch (_) {
      _error = 'The result could not be saved. Please try again.';
      return null;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resetCamera() async {
    try {
      await renderer.resetCamera();
    } catch (_) {
      _error = 'The camera could not be reset.';
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
