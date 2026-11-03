import 'dart:convert';

import 'package:chess_game/features/game/application/game_controller.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:chess_game/services/chess/chess_rules.dart';
import 'package:chess_game/services/stockfish/chess_engine.dart';
import 'package:chess_game/services/storage/local_storage.dart';
import 'package:chess_game/services/unity/board_renderer.dart';
import 'package:chess_game/services/unity/unity_bridge_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'processes Unity player.squareSelected JSON messages and replies with legalMoves.highlight and board.snapshot JSON',
    () async {
      final storage = MemoryLocalStorage();
      final renderer = MockUnityBoardRenderer();
      final controller = GameController(
        repository: storage,
        rules: const StandardChessRules(),
        engine: PlaceholderStockfishEngine(),
        renderer: renderer,
      );
      addTearDown(controller.dispose);

      final session = (await controller.start(
        const GameConfiguration(
          color: PlayerColor.white,
          difficulty: Difficulty.beginner,
        ),
      ))!;
      await controller.attachBoard(session.id);

      // 1. Unity sends player.squareSelected JSON for e2.
      final selectE2Json = UnityBridgeProtocol.encodeSquareSelected(
        messageId: 'u-select-1',
        sessionId: renderer.currentSessionId,
        gameId: session.id,
        revision: session.revision,
        sequence: 1,
        square: 'e2',
      );
      expect(renderer.receiveUnityMessageJson(selectE2Json), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(controller.selectedSquare, 'e2');
      expect(controller.legalMovesForSelection, containsAll(['e2e3', 'e2e4']));

      // Verify outbound legalMoves.highlight JSON sent to Unity.
      final lastOutbound =
          jsonDecode(renderer.outboundJsonMessages.last)
              as Map<String, Object?>;
      expect(lastOutbound['protocolVersion'], 1);
      expect(lastOutbound['type'], 'legalMoves.highlight');
      final highlightPayload =
          lastOutbound['payload'] as Map<String, Object?>;
      expect(highlightPayload['selectedSquare'], 'e2');
      expect(highlightPayload['inputEnabled'], isTrue);
      final moves = (highlightPayload['moves'] as List)
          .cast<Map<String, Object?>>();
      expect(
        moves.map((m) => m['to']),
        containsAll(['e3', 'e4']),
      );

      // 2. Unity sends player.squareSelected JSON for destination e4.
      final selectE4Json = UnityBridgeProtocol.encodeSquareSelected(
        messageId: 'u-select-2',
        sessionId: renderer.currentSessionId,
        gameId: session.id,
        revision: session.revision,
        sequence: 2,
        square: 'e4',
        selectionRequestId: lastOutbound['messageId'] as String?,
      );
      expect(renderer.receiveUnityMessageJson(selectE4Json), isTrue);
      await Future<void>.delayed(Duration.zero);

      final updated = controller.find(session.id)!;
      expect(updated.moves, ['e2e4']);
      expect(updated.revision, 1);

      // 3. When Flutter disables interaction (e.g. Black / AI turn), Unity taps are ignored.
      expect(renderer.inputEnabled, isFalse);
      final ignoredTapJson = UnityBridgeProtocol.encodeSquareSelected(
        messageId: 'u-select-3',
        sessionId: renderer.currentSessionId,
        gameId: session.id,
        revision: updated.revision,
        sequence: 3,
        square: 'd2',
      );
      expect(renderer.receiveUnityMessageJson(ignoredTapJson), isFalse);
      expect(controller.selectedSquare, isNull);
    },
  );
}
