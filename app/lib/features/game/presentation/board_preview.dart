import 'package:flutter/material.dart';

/// Decorative placeholder, never a second rules engine or interactive board.
class BoardPreview extends StatelessWidget {
  const BoardPreview({this.flipped = false, super.key});
  final bool flipped;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Non-interactive chessboard preview in the starting position. The 3D board is not connected.',
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
                                    child: ColoredBox(
                                      color: (row + col).isEven
                                          ? const Color(0xffe6e3dc)
                                          : const Color(0xff77766f),
                                      child: Center(
                                        child: Text(
                                          _piece(
                                            flipped ? 7 - row : row,
                                            flipped ? 7 - col : col,
                                          ),
                                          style: TextStyle(
                                            color: const Color(0xff161616),
                                            fontSize: constraints.maxWidth / 12,
                                            height: 1,
                                          ),
                                          textScaler: TextScaler.noScaling,
                                        ),
                                      ),
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

  String _piece(int row, int col) {
    const backBlack = ['♜', '♞', '♝', '♛', '♚', '♝', '♞', '♜'];
    const backWhite = ['♖', '♘', '♗', '♕', '♔', '♗', '♘', '♖'];
    return switch (row) {
      0 => backBlack[col],
      1 => '♟',
      6 => '♙',
      7 => backWhite[col],
      _ => '',
    };
  }
}
