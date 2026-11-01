import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';

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
              subtitle: 'Your sessions from this visit. Permanent game history is coming later.',
            ),
            const SizedBox(height: 28),
            if (controller.games.isEmpty) ...[
              const InfoPanel(
                title: 'A clean slate',
                icon: Icons.history_rounded,
                message: 'Open a preview session to get started. Your sessions will appear here.',
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
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(20),
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
                        '${game.configuration.color.label} · ${game.configuration.difficulty.label}\n${shortDate(game.startedAt)}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push(
                        game.isFinished
                            ? '/game/${game.id}/result'
                            : '/game/${game.id}',
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
