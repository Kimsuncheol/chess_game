/// Strict standard-chess FEN structure and basic setup consistency checks.
/// This is not a proof of historical reachability (see docs/chess_rules.md).
final class FenPosition {
  FenPosition._(this.fen, Map<String, String> pieces, this.fields)
    : pieces = Map.unmodifiable(pieces);

  final String fen;
  final Map<String, String> pieces;
  final List<String> fields;
  bool get whiteToMove => fields[1] == 'w';
  int get halfMoves => int.parse(fields[4]);
  int get fullMoves => int.parse(fields[5]);

  factory FenPosition.parse(String fen) {
    void invalid(String reason) =>
        throw FormatException('Invalid FEN: $reason');
    final fields = fen.trim().split(RegExp(r'\s+'));
    if (fields.length != 6) invalid('expected all six fields');
    final ranks = fields[0].split('/');
    if (ranks.length != 8) invalid('expected eight ranks');
    final pieces = <String, String>{};
    for (var row = 0; row < 8; row++) {
      var file = 0;
      var previousWasDigit = false;
      for (final symbol in ranks[row].split('')) {
        if (RegExp(r'^[1-8]$').hasMatch(symbol)) {
          if (previousWasDigit) invalid('adjacent empty-square counts');
          file += int.parse(symbol);
          previousWasDigit = true;
        } else {
          if (!RegExp(r'^[prnbqkPRNBQK]$').hasMatch(symbol) || file >= 8) {
            invalid('unknown piece or overflowing rank');
          }
          if (symbol.toLowerCase() == 'p' && (row == 0 || row == 7)) {
            invalid('unpromoted pawn on the first or eighth rank');
          }
          pieces['${String.fromCharCode(97 + file)}${8 - row}'] = symbol;
          file++;
          previousWasDigit = false;
        }
      }
      if (file != 8) invalid('each rank must contain eight squares');
    }
    for (final white in [true, false]) {
      final own = pieces.values
          .where((p) => (p == p.toUpperCase()) == white)
          .toList();
      int count(String piece) =>
          own.where((p) => p.toLowerCase() == piece).length;
      if (count('k') != 1) invalid('exactly one king per side is required');
      if (own.length > 16 || count('p') > 8) invalid('too many pieces');
      var promotions = 0;
      for (final entry in {'q': 1, 'r': 2, 'b': 2, 'n': 2}.entries) {
        final surplus = count(entry.key) - entry.value;
        if (surplus > 0) promotions += surplus;
      }
      if (promotions + count('p') > 8) invalid('impossible promotion budget');
    }
    if (fields[1] != 'w' && fields[1] != 'b') invalid('invalid side to move');
    if (fields[2] != '-' && !RegExp(r'^K?Q?k?q?$').hasMatch(fields[2])) {
      invalid('invalid standard castling rights');
    }
    for (final right in fields[2].split('')) {
      if (right == '-') continue;
      final white = right == right.toUpperCase();
      final rank = white ? '1' : '8';
      final rookFile = right.toLowerCase() == 'k' ? 'h' : 'a';
      if (pieces['e$rank'] != (white ? 'K' : 'k') ||
          pieces['$rookFile$rank'] != (white ? 'R' : 'r')) {
        invalid('castling right has no matching king and rook');
      }
    }
    if (!RegExp(r'^\d+$').hasMatch(fields[4]) ||
        !RegExp(r'^\d+$').hasMatch(fields[5]) ||
        int.tryParse(fields[4]) == null ||
        int.tryParse(fields[5]) == null ||
        int.parse(fields[5]) < 1) {
      invalid('invalid move counters');
    }
    if (fields[3] != '-') {
      if (!RegExp(r'^[a-h][36]$').hasMatch(fields[3])) {
        invalid('invalid en passant target');
      }
      final file = fields[3][0];
      final white = fields[1] == 'w';
      if (fields[3][1] != (white ? '6' : '3') ||
          pieces.containsKey(fields[3]) ||
          pieces['$file${white ? 5 : 4}'] != (white ? 'p' : 'P') ||
          pieces.containsKey('$file${white ? 7 : 2}') ||
          int.parse(fields[4]) != 0) {
        invalid('en passant target is inconsistent with a double pawn move');
      }
    }
    final canonical = [...fields];
    canonical[4] = int.parse(fields[4]).toString();
    canonical[5] = int.parse(fields[5]).toString();
    return FenPosition._(
      canonical.join(' '),
      pieces,
      List.unmodifiable(canonical),
    );
  }
}
