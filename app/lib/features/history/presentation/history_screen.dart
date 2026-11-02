import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';
import '../../game/domain/game_session.dart';
import '../../game/presentation/board_preview.dart';

Future<void> showGameMoveInspector(BuildContext context, GameSession game) =>
    showDialog<void>(
      context: context,
      builder: (_) => GameMoveInspectorDialog(game: game),
    );

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).game;
    return PageLayout(
      title: 'History',
      maxWidth: 800,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeading(
              'Every game, a little wiser.',
              subtitle:
                  'Your saved games on this device. Inspect move history or resume an open game.',
            ),
            const SizedBox(height: 28),
            if (controller.games.isEmpty) ...[
              const InfoPanel(
                title: 'A clean slate',
                icon: Icons.history_rounded,
                message:
                    'Start a game to build your history. Saved sessions and move lists will appear here.',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.push('/setup'),
                child: const Text('Set up a game'),
              ),
            ] else ...[
              for (final game in controller.games)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    key: ValueKey('history-game-${game.id}'),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              20,
                              16,
                              20,
                              8,
                            ),
                            leading: Icon(
                              game.isFinished
                                  ? Icons.flag_outlined
                                  : Icons.pause_circle_outline_rounded,
                            ),
                            title: Text(
                              game.isFinished
                                  ? '${game.result} · ${game.termination}'
                                  : 'Open session',
                            ),
                            subtitle: Text(
                              '${game.configuration.color.label} · ${game.configuration.difficulty.label}\n'
                              '${shortDate(game.endedAt ?? game.startedAt)} · '
                              '${game.moves.length} ${game.moves.length == 1 ? 'move' : 'moves'}',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => context.push(
                              game.isFinished
                                  ? '/game/${game.id}/result'
                                  : '/game/${game.id}',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  key: ValueKey('inspect-moves-${game.id}'),
                                  onPressed: () =>
                                      showGameMoveInspector(context, game),
                                  icon: const Icon(
                                    Icons.format_list_numbered_rounded,
                                  ),
                                  label: const Text('Inspect moves'),
                                ),
                                TextButton.icon(
                                  key: ValueKey('open-history-game-${game.id}'),
                                  onPressed: () => context.push(
                                    game.isFinished
                                        ? '/game/${game.id}/result'
                                        : '/game/${game.id}',
                                  ),
                                  icon: Icon(
                                    game.isFinished
                                        ? Icons.emoji_events_outlined
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    game.isFinished
                                        ? 'View result'
                                        : 'Continue game',
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
            ],
          ],
        ),
      ),
    );
  }
}

class GameMoveInspectorDialog extends StatefulWidget {
  const GameMoveInspectorDialog({required this.game, super.key});
  final GameSession game;

  @override
  State<GameMoveInspectorDialog> createState() =>
      _GameMoveInspectorDialogState();
}

class _GameMoveInspectorDialogState extends State<GameMoveInspectorDialog> {
  late int _selectedPly = widget.game.position.records.length;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final records = game.position.records;
    final replayFens = game.position.replayFens;
    final clampedPly = _selectedPly.clamp(0, replayFens.length - 1);
    final displayedFen = replayFens[clampedPly];
    final pairs = _buildTurnPairs(records);

    return AlertDialog(
      key: const ValueKey('move-inspector-dialog'),
      title: const Text('Move list'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                game.isFinished
                    ? '${game.result} · ${game.termination}'
                    : 'In progress · ${game.sideToMove.label} to move',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${game.configuration.color.label} pieces · '
                '${game.configuration.difficulty.label} opponent · '
                '${shortDate(game.endedAt ?? game.startedAt)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: BoardPreview(
                  flipped: game.humanColor == PlayerColor.black,
                  fen: displayedFen,
                ),
              ),
              if (records.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      key: const ValueKey('inspector-prev-ply'),
                      tooltip: 'Previous move',
                      onPressed: clampedPly > 0
                          ? () => setState(() => _selectedPly = clampedPly - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text(
                      clampedPly == 0
                          ? 'Starting position'
                          : 'After move $clampedPly of ${records.length} (${records[clampedPly - 1].san})',
                      key: const ValueKey('inspector-ply-label'),
                    ),
                    IconButton(
                      key: const ValueKey('inspector-next-ply'),
                      tooltip: 'Next move',
                      onPressed: clampedPly < records.length
                          ? () => setState(() => _selectedPly = clampedPly + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Recorded moves (${records.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (pairs.isEmpty)
                const Text(
                  'No moves recorded in this game.',
                  key: ValueKey('inspector-empty-moves'),
                )
              else
                Column(
                  key: const ValueKey('inspector-move-rows'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final pair in pairs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          pair.black == null
                              ? '${pair.turnNumber}. ${pair.white}'
                              : '${pair.turnNumber}. ${pair.white}   ${pair.black}',
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Text(
                'PGN',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  game.toPgn().trim(),
                  key: const ValueKey('inspector-pgn-text'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('close-move-inspector-button'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<_TurnMovePair> _buildTurnPairs(List<dynamic> records) {
    final result = <_TurnMovePair>[];
    for (var i = 0; i < widget.game.position.records.length; i += 2) {
      final whiteRecord = widget.game.position.records[i];
      final blackRecord = i + 1 < widget.game.position.records.length
          ? widget.game.position.records[i + 1]
          : null;
      result.add(
        _TurnMovePair(
          turnNumber: (i ~/ 2) + 1,
          white: '${whiteRecord.san} (${whiteRecord.uci})',
          black: blackRecord == null
              ? null
              : '${blackRecord.san} (${blackRecord.uci})',
        ),
      );
    }
    return result;
  }
}

class _TurnMovePair {
  const _TurnMovePair({
    required this.turnNumber,
    required this.white,
    this.black,
  });

  final int turnNumber;
  final String white;
  final String? black;
}
