import 'dart:convert';

import '../../features/game/domain/game_session.dart';
import 'board_renderer.dart';

/// Normative version 1 JSON protocol serializer and parser for the Flutter–Unity
/// chess bridge (`docs/unity_flutter_bridge.md`).
class UnityBridgeProtocol {
  const UnityBridgeProtocol._();

  static const int protocolVersion = 1;
  static const String typeUnityReady = 'unity.ready';
  static const String typeBoardSnapshot = 'board.snapshot';
  static const String typeSquareSelected = 'player.squareSelected';
  static const String typeLegalMovesHighlight = 'legalMoves.highlight';
  static const String typeGameStatus = 'game.status';
  static const String typeCameraReset = 'camera.reset';

  static final RegExp _squarePattern = RegExp(r'^[a-h][1-8]$');

  static bool isValidSquare(String? square) =>
      square != null && _squarePattern.hasMatch(square);

  /// Encodes a `board.snapshot` envelope (`Flutter -> Unity`).
  static String encodeBoardSnapshot({
    required BoardSnapshot snapshot,
    required String messageId,
    required String sessionId,
    required int sequence,
    String rendererInstanceId = 'unity-board-1',
    String? selectionRequestId,
    String? replyTo,
  }) {
    final highlightMoves = _buildHighlightMoves(snapshot.legalMoves);
    final hasHighlights =
        snapshot.selectedSquare != null || highlightMoves.isNotEmpty;

    final envelope = <String, Object?>{
      'protocolVersion': protocolVersion,
      'type': typeBoardSnapshot,
      'messageId': messageId,
      'sessionId': sessionId,
      'gameId': snapshot.gameId,
      'revision': snapshot.revision,
      'sequence': sequence,
      'replyTo': replyTo,
      'payload': <String, Object?>{
        'rendererInstanceId': rendererInstanceId,
        'fen': snapshot.fen,
        'selectedSquare': snapshot.selectedSquare,
        'highlights': hasHighlights
            ? <String, Object?>{
                'selectionRequestId': selectionRequestId ?? messageId,
                'selectedSquare': snapshot.selectedSquare,
                'moves': highlightMoves,
                'inputEnabled': snapshot.inputEnabled,
              }
            : null,
        'status': <String, Object?>{
          'phase': snapshot.phase.name,
          'sideToMove':
              snapshot.game.sideToMove == PlayerColor.white ? 'white' : 'black',
          'checkSquare': snapshot.game.position.status.checkSquare,
          'result': snapshot.game.result ?? '*',
          'termination': snapshot.game.termination,
          'canClaimDraw': snapshot.game.position.status.claims.isNotEmpty,
        },
        'pendingPromotion': snapshot.pendingPromotion == null
            ? null
            : <String, Object?>{
                'from': snapshot.pendingPromotion!.from,
                'to': snapshot.pendingPromotion!.to,
                'color': snapshot.pendingPromotion!.color.name,
                'choices': snapshot.pendingPromotion!.choices
                    .map((choice) => choice.uciCode)
                    .toList(),
                'presentation': 'flutter',
              },
        'camera': <String, Object?>{
          'orientation': snapshot.cameraFlipped ? 'black' : 'white',
          'preset': snapshot.cameraPreset,
        },
        'inputEnabled': snapshot.inputEnabled,
      },
    };

    return jsonEncode(envelope);
  }

  /// Encodes a `legalMoves.highlight` envelope (`Flutter -> Unity`).
  static String encodeLegalMovesHighlight({
    required String messageId,
    required String sessionId,
    required String gameId,
    required int revision,
    required int sequence,
    required String? selectedSquare,
    required List<String> legalMovesUci,
    required bool inputEnabled,
    String? replyTo,
  }) {
    final envelope = <String, Object?>{
      'protocolVersion': protocolVersion,
      'type': typeLegalMovesHighlight,
      'messageId': messageId,
      'sessionId': sessionId,
      'gameId': gameId,
      'revision': revision,
      'sequence': sequence,
      'replyTo': replyTo,
      'payload': <String, Object?>{
        'selectedSquare': selectedSquare,
        'moves': _buildHighlightMoves(legalMovesUci),
        'inputEnabled': inputEnabled,
      },
    };

    return jsonEncode(envelope);
  }

  /// Encodes a `player.squareSelected` envelope (`Unity -> Flutter`).
  static String encodeSquareSelected({
    required String messageId,
    required String sessionId,
    required String gameId,
    required int revision,
    required int sequence,
    required String square,
    String interaction = 'tap',
    String? selectionRequestId,
    String? replyTo,
  }) {
    final envelope = <String, Object?>{
      'protocolVersion': protocolVersion,
      'type': typeSquareSelected,
      'messageId': messageId,
      'sessionId': sessionId,
      'gameId': gameId,
      'revision': revision,
      'sequence': sequence,
      'replyTo': replyTo,
      'payload': <String, Object?>{
        'square': square,
        'interaction': interaction,
        'selectionRequestId': selectionRequestId,
      },
    };
    return jsonEncode(envelope);
  }

  /// Parses and validates an incoming `player.squareSelected` JSON envelope from Unity.
  /// Returns `null` if the JSON is malformed, uses an unsupported protocol version,
  /// or contains an invalid algebraic square.
  static BoardInteraction? tryParseSquareSelectedJson(
    String rawJson, {
    String? expectedSessionId,
  }) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, Object?>();

      if (map['protocolVersion'] != protocolVersion) return null;
      if (map['type'] != typeSquareSelected) return null;

      final sessionId = map['sessionId'];
      if (sessionId is! String || sessionId.isEmpty) return null;
      if (expectedSessionId != null && sessionId != expectedSessionId) {
        return null;
      }

      final gameId = map['gameId'];
      final revision = map['revision'];
      final payload = map['payload'];
      if (gameId is! String || gameId.isEmpty) return null;
      if (revision is! int || revision < 0) return null;
      if (payload is! Map) return null;

      final payloadMap = payload.cast<String, Object?>();
      final square = payloadMap['square'];
      final interaction = payloadMap['interaction'];
      if (square is! String || !isValidSquare(square)) return null;
      if (interaction is! String ||
          (interaction != 'tap' &&
              interaction != 'dragStart' &&
              interaction != 'dragEnd')) {
        return null;
      }

      return BoardInteraction(
        gameId: gameId,
        revision: revision,
        square: square,
      );
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, Object?>> _buildHighlightMoves(
    List<String> legalMovesUci,
  ) {
    final groupedPromotions = <String, List<String>>{};
    final orderedDestinations = <String>[];

    for (final uci in legalMovesUci) {
      if (uci.length < 4) continue;
      final to = uci.substring(2, 4);
      if (!isValidSquare(to)) continue;
      if (!groupedPromotions.containsKey(to)) {
        groupedPromotions[to] = <String>[];
        orderedDestinations.add(to);
      }
      if (uci.length == 5) {
        final promo = uci.substring(4, 5).toLowerCase();
        if (!groupedPromotions[to]!.contains(promo)) {
          groupedPromotions[to]!.add(promo);
        }
      }
    }

    return [
      for (final to in orderedDestinations)
        <String, Object?>{
          'to': to,
          'style': 'quiet',
          'promotionChoices': groupedPromotions[to] ?? const <String>[],
        },
    ];
  }
}
