import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';
import '../domain/game_session.dart';
import 'board_preview.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({required this.gameId, super.key});
  final String gameId;
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).game;
    return PageLayout(
      title: 'The board',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final game = controller.find(gameId);
          if (game == null) return const MissingGame();
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(
                game.isFinished ? 'Session complete.' : 'A fresh position.',
                subtitle:
                    '${game.configuration.color.label} pieces · ${game.configuration.difficulty.label} opponent',
              ),
              const SizedBox(height: 24),
              const InfoPanel(
                title: 'Board preview',
                icon: Icons.view_in_ar_outlined,
                message: 'The 3D board and offline opponent are not connected yet. Moves are unavailable in this preview.',
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Move list',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text('No moves yet. Every good game begins here.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.renderer.isAvailable
                        ? controller.resetCamera
                        : null,
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    label: const Text('Reset camera'),
                  ),
                  if (!game.isFinished)
                    OutlinedButton.icon(
                      onPressed: controller.busy
                          ? null
                          : () => _resign(context, game),
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Resign session'),
                    ),
                  if (game.isFinished)
                    FilledButton(
                      onPressed: () => context.go('/game/$gameId/result'),
                      child: const Text('View result'),
                    ),
                ],
              ),
              if (controller.error != null) ErrorNotice(controller.error!),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Save session & return home'),
              ),
              const SizedBox(height: 8),
              Text(
                'Session-only storage · Available until you close the app',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
          final board = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: BoardPreview(
              flipped: game.configuration.color == PlayerColor.black,
            ),
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 850 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.6;
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: board),
                        const SizedBox(width: 32),
                        Expanded(flex: 5, child: details),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: board),
                        const SizedBox(height: 28),
                        details,
                      ],
                    );
            },
          );
        },
      ),
    );
  }

  Future<void> _resign(BuildContext context, GameSession game) async {
    final controller = AppScope.of(context).game;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign this session?'),
        content: const Text(
          'This will end the session and add the result to your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep session'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resign'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final finished = await controller.resign(game.id);
    if (context.mounted && finished != null) {
      context.go('/game/${game.id}/result');
    }
  }
}

class MissingGame extends StatelessWidget {
  const MissingGame({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeading(
        'Session not found.',
        subtitle: 'Preview sessions are kept only while the app is open. Start a new one to continue.',
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => context.go('/setup'),
        child: const Text('Set up a game'),
      ),
    ],
  );
}
