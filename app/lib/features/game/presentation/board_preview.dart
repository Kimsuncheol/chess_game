import 'package:flutter/material.dart';

import '../domain/game_session.dart';

/// Decorative/mock board surface. Never acts as a second rules engine.
class BoardPreview extends StatelessWidget {
  const BoardPreview({
    this.flipped = false,
    this.fen = GameSession.initialFen,
    this.selectedSquare,
    this.highlightedSquares = const {},
    this.onSquareTap,
    super.key,
  });

  final bool flipped;
  final String fen;
  final String? selectedSquare;
  final Set<String> highlightedSquares;
  final ValueChanged<String>? onSquareTap;

  @override
  Widget build(BuildContext context) {
    final boardMatrix = _parseFenBoard(fen);
    return Semantics(
      label:
          'Non-interactive chessboard preview in the starting position. The 3D board is not connected.',
      image: true,
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BOARD PREVIEW',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(letterSpacing: 2),
                ),
                const SizedBox(height: 20),
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Column(
                        children: [
                          for (var row = 0; row < 8; row++)
                            Expanded(
                              child: Row(
                                children: [
                                  for (var col = 0; col < 8; col++)
                                    Expanded(
                                      child: _buildSquare(
                                        boardMatrix: boardMatrix,
                                        displayRow: row,
                                        displayCol: col,
                                        boardWidth: constraints.maxWidth,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'A new perspective on a classic.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSquare({
    required List<List<String>> boardMatrix,
    required int displayRow,
    required int displayCol,
    required double boardWidth,
  }) {
    final boardRow = flipped ? 7 - displayRow : displayRow;
    final boardCol = flipped ? 7 - displayCol : displayCol;
    final square = _squareName(boardRow, boardCol);
    final isSelected = selectedSquare == square;
    final isHighlighted = highlightedSquares.contains(square);
    final isLight = (displayRow + displayCol).isEven;

    final baseColor = isLight
        ? const Color(0xffe6e3dc)
        : const Color(0xff77766f);
    final color = isSelected
        ? const Color(0xffb5c7a3)
        : isHighlighted
            ? const Color(0xffc9d6b8)
            : baseColor;

    final cell = ColoredBox(
      key: ValueKey('board-square-$square'),
      color: color,
      child: Center(
        child: Text(
          boardMatrix[boardRow][boardCol],
          style: TextStyle(
            color: const Color(0xff161616),
            fontSize: boardWidth / 12,
            height: 1,
          ),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );

    if (onSquareTap == null) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSquareTap!(square),
      child: cell,
    );
  }

  static String _squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = 8 - row;
    return '$file$rank';
  }

  static List<List<String>> _parseFenBoard(String fen) {
    final grid = List.generate(8, (_) => List.filled(8, ''));
    final placement = fen.split(' ').first;
    final ranks = placement.split('/');
    for (var r = 0; r < ranks.length && r < 8; r++) {
      var c = 0;
      for (final rune in ranks[r].runes) {
        if (c >= 8) break;
        final ch = String.fromCharCode(rune);
        final emptyCount = int.tryParse(ch);
        if (emptyCount != null) {
          c += emptyCount;
        } else {
          grid[r][c] = _glyphForFenChar(ch);
          c++;
        }
      }
    }
    return grid;
  }

  static String _glyphForFenChar(String ch) => switch (ch) {
    'K' => '♔',
    'Q' => '♕',
    'R' => '♖',
    'B' => '♗',
    'N' => '♘',
    'P' => '♙',
    'k' => '♚',
    'q' => '♛',
    'r' => '♜',
    'b' => '♝',
    'n' => '♞',
    'p' => '♟',
    _ => '',
  };
}
