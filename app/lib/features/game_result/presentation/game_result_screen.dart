import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';
import '../../game/presentation/game_screen.dart';
import '../../history/presentation/history_screen.dart';

class GameResultScreen extends StatelessWidget {
  const GameResultScreen({required this.gameId, super.key});
  final String gameId;
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).game;
    return PageLayout(
      title: 'Game result',
      maxWidth: 680,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final game = controller.find(gameId);
          if (game == null) return const MissingGame();
          if (!game.isFinished) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeading('This session is still open.'),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/game/$gameId'),
                  child: const Text('Return to board'),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.flag_outlined, size: 48),
              const SizedBox(height: 24),
              const SectionHeading(
                'A moment to reflect.',
                subtitle: 'Your session has been added to history.',
              ),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Text(
                        game.result!,
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        game.termination!,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Played as ${game.configuration.color.label.toLowerCase()} · ${game.configuration.difficulty.label}',
                      ),
                      const SizedBox(height: 8),
                      Text(shortDate(game.endedAt ?? game.startedAt)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => context.go('/setup'),
                child: const Text('Set up another game'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('result-inspect-moves-button'),
                onPressed: () => showGameMoveInspector(context, game),
                icon: const Icon(Icons.format_list_numbered_rounded),
                label: const Text('Inspect moves'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/history'),
                child: const Text('View history'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Return home'),
              ),
            ],
          );
        },
      ),
    );
  }
}
