import 'dart:convert';

import 'package:bishop/bishop.dart' as bishop;
import 'package:chess_game/features/game/domain/chess/chess_position.dart';
import 'package:chess_game/features/game/domain/chess/fen_position.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:flutter_test/flutter_test.dart';

ChessPosition playAll(Iterable<String> moves, {ChessPosition? start}) {
  var position = start ?? ChessPosition.initial();
  for (final move in moves) {
    position = position.play(move);
  }
  return position;
}

const cycle = ['g1f3', 'g8f6', 'f3g1', 'f6g8'];
String? at(ChessPosition position, String square) =>
    FenPosition.parse(position.fen).pieces[square];
int perft(ChessPosition p, int depth) => depth == 0
    ? 1
    : p.legalMoves().fold(0, (n, m) => n + perft(p.play(m.uci), depth - 1));

void main() {
  group('move legality', () {
    test('initial destinations, turns, explicit promotion notation and immutable state', () {
      final initial = ChessPosition.initial();
      final next = initial.play('e2e4');
      expect(initial.legalMoves(), hasLength(20));
      expect(initial.legalDestinations('e2'), ['e3', 'e4']);
      expect(initial.legalDestinations('e7'), isEmpty);
      expect(initial.records, isEmpty);
      expect(initial.fen, standardInitialFen);
      expect(next.status.sideToMove, ChessSide.black);
      expect(next.legalDestinations('e2'), isEmpty);
      for (final move in ['d2d4', 'e2e5', 'E2E4']) {
        expect(() => next.play(move), throwsA(isA<ChessRuleException>()));
      }
      expect(
        () => initial.legalDestinations('z9'),
        throwsA(isA<ChessRuleException>()),
      );
      expect(() => initial.records.clear(), throwsUnsupportedError);
      expect(() => initial.repetitionCounts.clear(), throwsUnsupportedError);
    });
    test('pinned pieces cannot expose a king and checks must be answered', () {
      final pinned = ChessPosition.fromFen('k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1');
      expect(pinned.legalDestinations('e2'), isNot(contains('d2')));
      final checked = ChessPosition.fromFen('1k2r3/8/8/8/8/8/8/R3K3 w - - 0 1');
      expect(checked.status.inCheck, isTrue);
      expect(checked.status.checkSquare, 'e1');
      expect(checked.legalDestinations('a1'), isEmpty);
      expect(() => checked.play('a1a2'), throwsA(isA<ChessRuleException>()));
    });
    test('known initial and Kiwipete perft counts through application adapter', () {
      expect(perft(ChessPosition.initial(), 2), 400);
      final kiwi = ChessPosition.fromFen(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      );
      expect(kiwi.legalMoves(), hasLength(48));
      expect(perft(kiwi, 2), 2039);
    });
  });

  group('castling', () {
    for (final e in [
      ('w', 'e1g1', 'g1', 'f1', 'h1', 'K', 'R', 'O-O'),
      ('w', 'e1c1', 'c1', 'd1', 'a1', 'K', 'R', 'O-O-O'),
      ('b', 'e8g8', 'g8', 'f8', 'h8', 'k', 'r', 'O-O'),
      ('b', 'e8c8', 'c8', 'd8', 'a8', 'k', 'r', 'O-O-O'),
    ]) {
      test('moves both pieces for ${e.$2}', () {
        final start = ChessPosition.fromFen(
          'r3k2r/8/8/8/8/8/8/R3K2R ${e.$1} KQkq - 0 1',
        );
        expect(
          start.legalMoves().singleWhere((m) => m.uci == e.$2).isCastling,
          isTrue,
        );
        final next = start.play(e.$2);
        expect(at(next, e.$3), e.$6);
        expect(at(next, e.$4), e.$7);
        expect(at(next, e.$5), isNull);
        expect(next.records.last.san, e.$8);
        expect(
          FenPosition.parse(next.fen).fields[2],
          e.$1 == 'w' ? 'kq' : 'KQ',
        );
      });
    }
    test(
      'cannot castle through attack, out of check, or through occupied squares',
      () {
        final through = ChessPosition.fromFen(
          'r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1',
        );
        expect(through.legalDestinations('e1'), isNot(contains('g1')));
        expect(through.legalDestinations('e1'), contains('c1'));
        final checked = ChessPosition.fromFen(
          '4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1',
        );
        expect(
          checked.legalDestinations('e1'),
          isNot(anyOf(contains('g1'), contains('c1'))),
        );
        expect(ChessPosition.initial().legalDestinations('e1'), isEmpty);
      },
    );
    test('capture of a corner rook removes its castling right', () {
      final start = ChessPosition.fromFen(
        'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
      );
      final next = start.play('a1a8');
      expect(FenPosition.parse(next.fen).fields[2], 'Kk');
    });
    test(
      'returning rook does not restore castling rights or repetition identity',
      () {
        final start = ChessPosition.fromFen(
          'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
        );
        final next = playAll(['h1h2', 'a8a7', 'h2h1', 'a7a8'], start: start);
        expect(next.legalDestinations('e1'), isNot(contains('g1')));
        expect(next.status.repetitionCount, 1);
      },
    );
  });

  group('en passant and promotion', () {
    test('white en passant removes the pawn and expires after one reply', () {
      final initial = ChessPosition.fromFen(
        '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2',
      );
      final move = initial.legalMoves().singleWhere((m) => m.uci == 'e5d6');
      expect(move.isEnPassant, isTrue);
      expect(move.isCapture, isTrue);
      final next = initial.play('e5d6');
      expect(at(next, 'd5'), isNull);
      expect(at(next, 'e5'), isNull);
      expect(at(next, 'd6'), 'P');
      expect(next.records.single.san, 'exd6');
      final expired = playAll(['e1f1', 'e8f8'], start: initial);
      expect(() => expired.play('e5d6'), throwsA(isA<ChessRuleException>()));
    });
    test('black en passant removes the pawn on its actual square', () {
      final next = ChessPosition.fromFen('4k3/8/8/8/3Pp3/8/8/4K3 b - d3 0 2')
          .play('e4d3');
      expect(at(next, 'd4'), isNull);
      expect(at(next, 'd3'), 'p');
    });
    test(
      'pinned en passant is illegal and excluded from repetition identity',
      () {
        const fen = 'k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 2';
        final pinned = ChessPosition.fromFen(fen);
        expect(pinned.legalDestinations('e5'), isNot(contains('d6')));
        expect(
          pinned.repetitionCounts.keys.single,
          ChessPosition.fromFen(fen.replaceFirst('d6', '-'))
              .repetitionCounts
              .keys
              .single,
        );
        const legal = '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2';
        expect(
          ChessPosition.fromFen(legal).repetitionCounts.keys.single,
          isNot(
            ChessPosition.fromFen(legal.replaceFirst('d6', '-'))
                .repetitionCounts
                .keys
                .single,
          ),
        );
      },
    );
    for (final choice in ['q', 'r', 'b', 'n']) {
      test(
        'explicit white promotion to $choice with deduplicated destinations',
        () {
          final initial = ChessPosition.fromFen(
            '7k/4P3/8/8/8/8/8/K7 w - - 0 1',
          );
          expect(initial.legalDestinations('e7'), ['e8']);
          expect(initial.promotionChoices('e7', 'e8'), ['b', 'n', 'q', 'r']);
          expect(
            () => initial.play('e7e8'),
            throwsA(isA<ChessRuleException>()),
          );
          final next = initial.play('e7e8$choice');
          expect(at(next, 'e8'), choice.toUpperCase());
          expect(next.status.halfMoveClock, 0);
          expect(
            next.records.single.san,
            startsWith('e8=${choice.toUpperCase()}'),
          );
        },
      );
    }
    for (final choice in ['q', 'r', 'b', 'n']) {
      test('black promotion to $choice uses the chosen piece', () {
        final next = ChessPosition.fromFen('7k/8/8/8/8/8/4p3/K7 b - - 0 1')
            .play('e2e1$choice');
        expect(at(next, 'e1'), choice);
      });
    }
    test('black capture-promotion removes rook and records SAN', () {
      final next = ChessPosition.fromFen('7k/8/8/8/8/8/1p6/R6K b - - 0 1')
          .play('b2a1n');
      expect(at(next, 'a1'), 'n');
      expect(at(next, 'b2'), isNull);
      expect(next.records.single.san, 'bxa1=N');
    });
  });

  group('game endings', () {
    test(
      'Fool’s mate is checkmate and forbids further moves; undo reopens it',
      () {
        final mate = playAll(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
        expect(mate.status.isCheckmate, isTrue);
        expect(mate.status.inCheck, isTrue);
        expect(mate.status.result, '0-1');
        expect(mate.records.last.san, 'Qh4#');
        expect(mate.legalMoves(), isEmpty);
        expect(() => mate.play('e2e4'), throwsA(isA<ChessRuleException>()));
        expect(mate.undo().status.isFinished, isFalse);
      },
    );
    test('stalemate has no check and is automatic', () {
      final p = ChessPosition.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(p.status.isStalemate, isTrue);
      expect(p.status.inCheck, isFalse);
      expect(p.status.termination, ChessTermination.stalemate);
      expect(p.status.result, '1/2-1/2');
    });
    for (final fen in [
      '7k/8/8/8/8/8/8/K7 w - - 0 1',
      '7k/8/8/8/8/8/8/K1B5 w - - 0 1',
      '7k/8/8/8/8/8/8/KN6 w - - 0 1',
      '5b1k/8/8/8/8/8/8/K1B5 w - - 0 1',
    ]) {
      test('supported insufficient material: $fen', () {
        expect(
          ChessPosition.fromFen(fen).status.termination,
          ChessTermination.insufficientMaterial,
        );
      });
    }
    test(
      'two knights and opposite-colored bishops are not falsely declared dead',
      () {
        expect(
          ChessPosition.fromFen('7k/8/8/8/8/8/8/KNN5 w - - 0 1')
              .status
              .isFinished,
          isFalse,
        );
        expect(
          ChessPosition.fromFen('4b2k/8/8/8/8/8/8/K1B5 w - - 0 1')
              .status
              .isFinished,
          isFalse,
        );
      },
    );
    test('third repetition is claimable; fifth repetition is automatic', () {
      final three = playAll([...cycle, ...cycle]);
      expect(three.status.repetitionCount, 3);
      expect(three.status.isFinished, isFalse);
      expect(three.status.claims, contains(DrawClaim.threefoldRepetition));
      final claimed = three.claimDraw(DrawClaim.threefoldRepetition);
      expect(claimed.status.termination, ChessTermination.threefoldClaim);
      expect(claimed.fen, three.fen);
      expect(three.status.isFinished, isFalse);
      final five = playAll([...cycle, ...cycle, ...cycle, ...cycle]);
      expect(five.status.repetitionCount, 5);
      expect(five.status.termination, ChessTermination.fivefoldRepetition);
    });
    test('claim by intended move validates but does not execute that move', () {
      final before = playAll([...cycle, ...cycle.take(3)]);
      expect(before.canClaim(DrawClaim.threefoldRepetition), isFalse);
      expect(
        before.canClaim(DrawClaim.threefoldRepetition, intendedMove: 'f6g8'),
        isTrue,
      );
      final claimed = before.claimDraw(
        DrawClaim.threefoldRepetition,
        intendedMove: 'f6g8',
      );
      expect(claimed.fen, before.fen);
      expect(claimed.records, hasLength(7));
      expect(claimed.status.sideToMove, ChessSide.black);
      expect(
        ChessPosition.fromJson(claimed.toJson()).status.termination,
        ChessTermination.threefoldClaim,
      );
    });
    test(
      '50 moves is claimable after 100 plies, including an intended move',
      () {
        final before = ChessPosition.fromFen(
          '4k2r/8/8/8/8/8/8/R3K3 w - - 99 50',
        );
        expect(before.canClaim(DrawClaim.fiftyMove), isFalse);
        final claimed = before.claimDraw(
          DrawClaim.fiftyMove,
          intendedMove: 'a1a2',
        );
        expect(claimed.status.termination, ChessTermination.fiftyMoveClaim);
        expect(claimed.fen, before.fen);
        final next = before.play('a1a2');
        expect(next.status.isFinished, isFalse);
        expect(next.status.claims, contains(DrawClaim.fiftyMove));
        expect(next.claimDraw(DrawClaim.fiftyMove).status.result, '1/2-1/2');
        expect(
          () => ChessPosition.initial().claimDraw(DrawClaim.fiftyMove),
          throwsA(isA<ChessRuleException>()),
        );
      },
    );
    test('pawn moves and captures reset the half-move clock', () {
      final pawn = ChessPosition.fromFen('4k2r/8/8/8/8/8/P7/R3K3 w - - 99 50')
          .play('a2a3');
      final capture = ChessPosition.fromFen('4k3/8/8/8/8/8/r7/R3K3 w - - 99 50')
          .play('a1a2');
      for (final p in [pawn, capture]) {
        expect(p.status.halfMoveClock, 0);
        expect(p.status.claims, isEmpty);
      }
    });
    test(
      '75 moves is automatic after 150 plies; checkmate takes precedence',
      () {
        final draw = ChessPosition.fromFen('4k2r/8/8/8/8/8/8/R3K3 w - - 149 75')
            .play('a1a2');
        expect(draw.status.termination, ChessTermination.seventyFiveMove);
        final mate = ChessPosition.fromFen('7k/5K2/6Q1/8/8/8/8/8 w - - 149 75')
            .play('g6g7');
        expect(mate.status.halfMoveClock, 150);
        expect(mate.status.termination, ChessTermination.checkmate);
        expect(mate.status.result, '1-0');
      },
    );
  });

  group('FEN, restore, replay and PGN', () {
    test(
      'FEN loses prior repetition history; saved aggregate preserves it',
      () {
        final p = playAll([...cycle, ...cycle]);
        final fenOnly = ChessPosition.fromFen(p.fen);
        expect(fenOnly.fen, p.fen);
        expect(fenOnly.records, isEmpty);
        expect(fenOnly.status.repetitionCount, 1);
        final restored = ChessPosition.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
        );
        expect(restored.fen, p.fen);
        expect(restored.status.repetitionCount, 3);
        expect(restored.records.map((m) => m.san), p.records.map((m) => m.san));
        expect(restored.replayFens, hasLength(9));
        expect(restored.replayFens.first, standardInitialFen);
        expect(restored.replayFens.last, p.fen);
      },
    );
    test('tampered FEN/result and illegal histories fail restoration', () {
      final p = ChessPosition.initial().play('e2e4');
      expect(
        () =>
            ChessPosition.fromJson({...p.toJson(), 'fen': standardInitialFen}),
        throwsFormatException,
      );
      expect(
        () => ChessPosition.fromJson({...p.toJson(), 'result': '1-0'}),
        throwsFormatException,
      );
      expect(
        () => ChessPosition.fromJson({
          ...p.toJson(),
          'moves': ['e2e5'],
        }),
        throwsA(isA<ChessRuleException>()),
      );
      expect(
        () => ChessPosition.fromJson({...p.toJson(), 'schemaVersion': 42}),
        throwsFormatException,
      );
    });
    for (final fen in [
      '8/8/8/8/8/8/8/8 w - - 0 1',
      '7k/8/8/8/8/8/8/K7 w - -',
      '7k/8/8/8/8/8/8/KK6 w - - 0 1',
      '7k/8/8/8/8/8/8/K7 x - - 0 1',
      '7k/8/8/8/8/8/8/K7 w K - 0 1',
      '7k/8/8/8/8/8/8/K7 w - d6 0 1',
      '7k/8/8/8/8/8/8/K7 w - - -1 1',
      '7k/8/8/8/8/8/8/K7 w - - 0 0',
      '7k/P7/8/8/8/8/8/K7 w - - 0 1 extra',
      'P6k/8/8/8/8/8/8/K7 w - - 0 1',
      '8/8/8/8/8/8/1k6/K7 w - - 0 1',
      '7k/7R/8/8/8/8/8/K7 w - - 0 1',
    ]) {
      test('rejects inconsistent/malformed setup $fen', () {
        expect(() => ChessPosition.fromFen(fen), throwsFormatException);
      });
    }
    test(
      'SAN and result export as a parseable PGN mainline with escaped tags',
      () {
        final p = playAll(['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6']);
        final pgn = p.toPgn(
          headers: {'White': 'A "quoted" player', 'Result': '1-0'},
        );
        expect(pgn, contains('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *'));
        expect(pgn, contains('[Result "*"]'));
        expect(pgn, contains(r'[White "A \"quoted\" player"]'));
        expect(bishop.Game.fromPgn(pgn).fen, p.fen);
        final mate = playAll(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
        expect(mate.toPgn(), contains('2. g4 Qh4# 0-1'));
      },
    );
    test(
      'custom black-to-move starts have SetUp/FEN and correct numbering',
      () {
        final start = ChessPosition.fromFen('4k2r/8/8/8/8/8/8/R3K3 b - - 0 42');
        final p = playAll(['h8h7', 'a1a2'], start: start);
        final pgn = p.toPgn();
        expect(pgn, contains('[SetUp "1"]'));
        expect(pgn, contains('[FEN "${start.fen}"]'));
        expect(pgn, contains('42... Rh7 43. Ra2 *'));
        expect(bishop.Game.fromPgn(pgn).fen, p.fen);
      },
    );
    test('session restore, undo, resignation and PGN keep revision/metadata consistent', () {
      final now = DateTime(2026, 11, 2);
      final initial = GameSession(
        id: 'game',
        configuration: const GameConfiguration(),
        startedAt: now,
      );
      final played = initial.play('e2e4', now).play('e7e5', now);
      final restored = GameSession.fromJson(
        jsonDecode(jsonEncode(played.toJson())) as Map<String, dynamic>,
      );
      expect(restored.fen, played.fen);
      expect(restored.moves, ['e2e4', 'e7e5']);
      final undone = restored.undo(now);
      expect(undone.revision, played.revision + 1);
      expect(undone.moves, ['e2e4']);
      final ended = undone.resign(now);
      expect(GameSession.fromJson(ended.toJson()).result, '0-1');
      expect(ended.toPgn(), contains('[Result "0-1"]'));
    });
  });
}
