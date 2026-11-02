import 'package:bishop/bishop.dart' as bishop;

import 'fen_position.dart';

const standardInitialFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

enum ChessSide {
  white,
  black;

  ChessSide get opposite => this == white ? black : white;
}

enum DrawClaim { threefoldRepetition, fiftyMove }

enum ChessTermination {
  checkmate('Checkmate'),
  stalemate('Stalemate'),
  insufficientMaterial('Insufficient material'),
  fivefoldRepetition('Fivefold repetition'),
  seventyFiveMove('Seventy-five-move rule'),
  threefoldClaim('Threefold repetition claim'),
  fiftyMoveClaim('Fifty-move rule claim'),
  resignation('Resignation');

  const ChessTermination(this.label);
  final String label;
}

final class ChessRuleException implements Exception {
  const ChessRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class ChessMoveRecord {
  const ChessMoveRecord({
    required this.uci,
    required this.san,
    required this.beforeFen,
    required this.afterFen,
  });
  final String uci;
  final String san;
  final String beforeFen;
  final String afterFen;
}

final class LegalChessMove {
  const LegalChessMove({
    required this.uci,
    required this.isCapture,
    required this.isCastling,
    required this.isEnPassant,
  });
  final String uci;
  final bool isCapture;
  final bool isCastling;
  final bool isEnPassant;
  String get from => uci.substring(0, 2);
  String get to => uci.substring(2, 4);
  String? get promotion => uci.length == 5 ? uci[4] : null;
}

final class ChessStatus {
  ChessStatus._({
    required this.sideToMove,
    required this.inCheck,
    required this.checkSquare,
    required this.isCheckmate,
    required this.isStalemate,
    required this.isInsufficientMaterial,
    required this.halfMoveClock,
    required this.repetitionCount,
    required Set<DrawClaim> claims,
    this.result = '*',
    this.termination,
  }) : claims = Set.unmodifiable(claims);
  final ChessSide sideToMove;
  final bool inCheck;
  final String? checkSquare;
  final bool isCheckmate;
  final bool isStalemate;
  final bool isInsufficientMaterial;
  final int halfMoveClock;
  final int repetitionCount;
  final Set<DrawClaim> claims;
  final String result;
  final ChessTermination? termination;
  bool get isFinished => result != '*';

  ChessStatus _end(String result, ChessTermination reason) => ChessStatus._(
    sideToMove: sideToMove,
    inCheck: inCheck,
    checkSquare: checkSquare,
    isCheckmate: isCheckmate,
    isStalemate: isStalemate,
    isInsufficientMaterial: isInsufficientMaterial,
    halfMoveClock: halfMoveClock,
    repetitionCount: repetitionCount,
    claims: {},
    result: result,
    termination: reason,
  );
}

/// The authoritative, immutable standard-chess aggregate. No Flutter or Unity
/// types, mutable Bishop objects or externally writable collections escape it.
final class ChessPosition {
  ChessPosition._({
    required this.initialFen,
    required this.fen,
    required List<ChessMoveRecord> records,
    required Map<String, int> repetitionCounts,
    required this.status,
    this.intendedClaimMove,
    this.resignedSide,
  }) : records = List.unmodifiable(records),
       repetitionCounts = Map.unmodifiable(repetitionCounts);

  static const rulesVersion = 'standard-v1-bishop-1.4.4';
  final String initialFen;
  final String fen;
  final List<ChessMoveRecord> records;
  final Map<String, int> repetitionCounts;
  final ChessStatus status;
  final String? intendedClaimMove;
  final ChessSide? resignedSide;

  static final _variant = bishop.Variant.standard().copyWith(
    halfMoveDraw: 150,
    repetitionDraw: 5,
    // Bishop's material heuristic is replaced with the supported dead classes.
    materialConditions: bishop.MaterialConditions.none,
  );

  factory ChessPosition.initial() => ChessPosition.fromFen(standardInitialFen);

  /// Importing FEN starts a new history; prior repetitions cannot be recovered.
  factory ChessPosition.fromFen(String fen) {
    final parsed = FenPosition.parse(fen);
    final game = _engine(parsed.fen);
    // The side that just moved cannot have left its own king in check. Also
    // rejects adjacent kings and positions with both kings checked.
    final other = game.turn == bishop.Bishop.white
        ? bishop.Bishop.black
        : bishop.Bishop.white;
    if (game.kingAttacked(other)) {
      throw const FormatException(
        'Invalid FEN: the side not to move is in check',
      );
    }
    final canonical = game.fen;
    final key = _key(game);
    return ChessPosition._(
      initialFen: canonical,
      fen: canonical,
      records: [],
      repetitionCounts: {key: 1},
      status: _status(game, 1),
    );
  }

  static bishop.Game _engine(String fen) =>
      bishop.Game(variant: _variant, fen: fen);

  /// Excludes counters and includes EP only if a *legal* EP capture exists.
  /// In particular, a pinned en passant pawn does not change repetition identity.
  static String _key(bishop.Game game) {
    final fields = game.fen.split(' ');
    final ep = game.generateLegalMoves().any(
      (m) => m is bishop.StandardMove && m.enPassant,
    );
    return '${fields[0]} ${fields[1]} ${fields[2]} ${ep ? fields[3] : '-'}';
  }

  static bool _insufficient(String fen) {
    final pieces = FenPosition.parse(fen).pieces.entries
        .where((e) => e.value.toLowerCase() != 'k')
        .toList();
    if (pieces.isEmpty) return true;
    if (pieces.length == 1 &&
        ['b', 'n'].contains(pieces.single.value.toLowerCase())) {
      return true;
    }
    if (pieces.every((e) => e.value.toLowerCase() == 'b')) {
      final colors = pieces
          .map((e) => (e.key.codeUnitAt(0) - 97 + int.parse(e.key[1]) - 1) % 2)
          .toSet();
      return colors.length == 1;
    }
    // No false draw for KNN vs K or opposite-colored bishops. Other dead
    // positions (e.g. locked pawn structures) are intentionally not solved.
    return false;
  }

  static ChessStatus _status(bishop.Game game, int repetitions) {
    final legal = game.generateLegalMoves();
    final check = game.inCheck;
    final mate = check && legal.isEmpty;
    final stale = !check && legal.isEmpty;
    final insufficient = _insufficient(game.fen);
    final side = game.turn == bishop.Bishop.white
        ? ChessSide.white
        : ChessSide.black;
    final state = ChessStatus._(
      sideToMove: side,
      inCheck: check,
      checkSquare: game.info.checkSq,
      isCheckmate: mate,
      isStalemate: stale,
      isInsufficientMaterial: insufficient,
      halfMoveClock: game.state.halfMoves,
      repetitionCount: repetitions,
      claims: {
        if (repetitions >= 3) DrawClaim.threefoldRepetition,
        if (game.state.halfMoves >= 100) DrawClaim.fiftyMove,
      },
    );
    if (mate) {
      return state._end(
        side == ChessSide.white ? '0-1' : '1-0',
        ChessTermination.checkmate,
      );
    }
    if (stale) return state._end('1/2-1/2', ChessTermination.stalemate);
    if (insufficient) {
      return state._end('1/2-1/2', ChessTermination.insufficientMaterial);
    }
    if (repetitions >= 5) {
      return state._end('1/2-1/2', ChessTermination.fivefoldRepetition);
    }
    if (game.state.halfMoves >= 150) {
      return state._end('1/2-1/2', ChessTermination.seventyFiveMove);
    }
    return state;
  }

  List<LegalChessMove> legalMoves({String? from}) {
    if (status.isFinished) return const [];
    if (from != null && !RegExp(r'^[a-h][1-8]$').hasMatch(from)) {
      throw const ChessRuleException('Use a square such as e2.');
    }
    final game = _engine(fen);
    return List.unmodifiable(
      game
          .generateLegalMoves()
          .whereType<bishop.StandardMove>()
          .map(
            (move) => LegalChessMove(
              uci: game.toAlgebraic(move),
              isCapture: move.capture,
              isCastling: move.castling,
              isEnPassant: move.enPassant,
            ),
          )
          .where((move) => from == null || move.from == from),
    );
  }

  List<String> legalDestinations(String from) => List.unmodifiable(
    legalMoves(from: from).map((m) => m.to).toSet().toList()..sort(),
  );
  List<String> promotionChoices(String from, String to) => List.unmodifiable(
    legalMoves(from: from)
        .where((m) => m.to == to && m.promotion != null)
        .map((m) => m.promotion!)
        .toList()
      ..sort(),
  );

  ChessPosition play(String uci) {
    _requireActive();
    if (!RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(uci)) {
      throw const ChessRuleException(
        'Use a complete UCI move, including a promotion choice when required.',
      );
    }
    final game = _engine(fen);
    // Bishop.makeMove accepts prebuilt moves; always select from legal moves.
    final move = game.getMove(uci);
    if (move == null) {
      throw ChessRuleException('The move $uci is not legal in this position.');
    }
    final san = game.toSan(move);
    if (!game.makeMove(move, false)) {
      throw const ChessRuleException('The move could not be applied.');
    }
    final after = game.fen;
    final key = _key(game);
    final repetitions = {
      ...repetitionCounts,
      key: (repetitionCounts[key] ?? 0) + 1,
    };
    return ChessPosition._(
      initialFen: initialFen,
      fen: after,
      records: [
        ...records,
        ChessMoveRecord(uci: uci, san: san, beforeFen: fen, afterFen: after),
      ],
      repetitionCounts: repetitions,
      status: _status(game, repetitions[key]!),
    );
  }

  bool canClaim(DrawClaim claim, {String? intendedMove}) {
    if (status.isFinished) return false;
    if (intendedMove == null) return status.claims.contains(claim);
    final proposed = play(intendedMove); // validates without committing
    return claim == DrawClaim.fiftyMove
        ? proposed.status.halfMoveClock >= 100
        : proposed.status.repetitionCount >= 3;
  }

  /// A claim by intended move does not execute that move or alter turn/FEN.
  ChessPosition claimDraw(DrawClaim claim, {String? intendedMove}) {
    _requireActive();
    if (!canClaim(claim, intendedMove: intendedMove)) {
      throw const ChessRuleException('This draw cannot be claimed.');
    }
    return _end(
      '1/2-1/2',
      claim == DrawClaim.fiftyMove
          ? ChessTermination.fiftyMoveClaim
          : ChessTermination.threefoldClaim,
      intendedMove: intendedMove,
    );
  }

  ChessPosition resign(ChessSide side) {
    _requireActive();
    // A bare opposing king cannot possibly mate, even with cooperation.
    final pieces = FenPosition.parse(fen).pieces.values.where(
      (p) => (p == p.toUpperCase()) == (side.opposite == ChessSide.white),
    );
    if (pieces.length == 1) {
      return _end('1/2-1/2', ChessTermination.resignation, resigning: side);
    }
    return _end(
      side == ChessSide.white ? '0-1' : '1-0',
      ChessTermination.resignation,
      resigning: side,
    );
  }

  ChessPosition _end(
    String result,
    ChessTermination reason, {
    String? intendedMove,
    ChessSide? resigning,
  }) => ChessPosition._(
    initialFen: initialFen,
    fen: fen,
    records: records,
    repetitionCounts: repetitionCounts,
    status: status._end(result, reason),
    intendedClaimMove: intendedMove,
    resignedSide: resigning,
  );

  void _requireActive() {
    if (status.isFinished) {
      throw const ChessRuleException('The game has already ended.');
    }
  }

  ChessPosition undo({int plies = 1}) {
    if (plies < 1 || plies > records.length) {
      throw const ChessRuleException('There are not enough moves to undo.');
    }
    return ChessPosition.restore(
      initialFen: initialFen,
      moves: records.take(records.length - plies).map((m) => m.uci),
    );
  }

  List<String> get replayFens =>
      List.unmodifiable([initialFen, ...records.map((m) => m.afterFen)]);

  factory ChessPosition.restore({
    required String initialFen,
    required Iterable<String> moves,
    String? expectedFen,
  }) {
    var position = ChessPosition.fromFen(initialFen);
    for (final move in moves) {
      position = position.play(move);
    }
    if (expectedFen != null &&
        position.fen != FenPosition.parse(expectedFen).fen) {
      throw const FormatException(
        'Saved FEN does not match the legal move history.',
      );
    }
    return position;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'rulesVersion': rulesVersion,
    'initialFen': initialFen,
    'fen': fen,
    'moves': records.map((m) => m.uci).toList(),
    'result': status.result,
    'termination': status.termination?.name,
    'intendedClaimMove': intendedClaimMove,
    'resignedSide': resignedSide?.name,
  };

  factory ChessPosition.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1 ||
        json['rulesVersion'] != rulesVersion ||
        json['initialFen'] is! String ||
        json['fen'] is! String ||
        json['moves'] is! List ||
        !(json['moves'] as List).every((m) => m is String)) {
      throw const FormatException(
        'Unsupported or malformed saved chess state.',
      );
    }
    var position = ChessPosition.restore(
      initialFen: json['initialFen'] as String,
      moves: (json['moves'] as List).cast<String>(),
      expectedFen: json['fen'] as String,
    );
    if (json['resignedSide'] != null) {
      if (json['intendedClaimMove'] != null) {
        throw const FormatException(
          'A resignation cannot contain a draw claim move.',
        );
      }
      final side = ChessSide.values
          .where((s) => s.name == json['resignedSide'])
          .firstOrNull;
      if (side == null) {
        throw const FormatException('Invalid saved resigning side.');
      }
      position = position.resign(side);
    } else if (json['termination'] == ChessTermination.threefoldClaim.name ||
        json['termination'] == ChessTermination.fiftyMoveClaim.name) {
      if (json['intendedClaimMove'] != null &&
          json['intendedClaimMove'] is! String) {
        throw const FormatException('Invalid intended claim move.');
      }
      position = position.claimDraw(
        json['termination'] == ChessTermination.threefoldClaim.name
            ? DrawClaim.threefoldRepetition
            : DrawClaim.fiftyMove,
        intendedMove: json['intendedClaimMove'] as String?,
      );
    } else if (json['intendedClaimMove'] != null) {
      throw const FormatException('Unexpected intended claim move.');
    }
    if (position.status.result != json['result'] ||
        position.status.termination?.name != json['termination']) {
      throw const FormatException(
        'Saved result does not match the adjudicated position.',
      );
    }
    return position;
  }

  /// Exports a single PGN mainline. Variations, clocks and annotations are not stored.
  String toPgn({Map<String, String> headers = const {}}) {
    if (headers.keys.any(
      (key) => !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(key),
    )) {
      throw const FormatException('Invalid PGN tag name.');
    }
    final tags = <String, String>{
      'Event': 'Still Chess',
      'Site': 'Local',
      'Date': '????.??.??',
      'Round': '?',
      'White': '?',
      'Black': '?',
      ...headers,
      'Result': status.result,
    };
    tags.remove('Variant');
    tags.remove('FEN');
    tags.remove('SetUp');
    if (initialFen != standardInitialFen) {
      tags['SetUp'] = '1';
      tags['FEN'] = initialFen;
    }
    String escape(String value) => value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll(RegExp(r'[\r\n\x00-\x1f]'), ' ');
    final initial = FenPosition.parse(initialFen);
    var number = initial.fullMoves;
    var white = initial.whiteToMove;
    final tokens = <String>[];
    for (var i = 0; i < records.length; i++) {
      if (white) {
        tokens.add('$number.');
      } else if (i == 0) {
        tokens.add('$number...');
      }
      tokens.add(records[i].san);
      if (!white) number++;
      white = !white;
    }
    tokens.add(status.result);
    return '${tags.entries.map((e) => '[${e.key} "${escape(e.value)}"]').join('\n')}\n\n${tokens.join(' ')}\n';
  }
}
