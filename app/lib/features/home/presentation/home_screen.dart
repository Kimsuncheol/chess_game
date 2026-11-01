import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';
import '../../game/presentation/board_preview.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).game;
    return PageLayout(
      title: 'Still Chess',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          // Only repository-backed, unfinished sessions qualify. Never seed a
          // demo game to make Continue Game appear. Visible text supplies each
          // Material button's accessible name without duplicate semantics.
          final active = controller.activeGame;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR NEXT GOOD MOVE',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(letterSpacing: 2),
              ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(
                  'Make room\nfor a little chess.',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.8,
                    height: 1.12,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'A quiet place to think. A fresh way to see the board.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.pushNamed('setup'),
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Play vs AI'),
                  ),
                  if (active != null)
                    OutlinedButton.icon(
                      onPressed: () => context.pushNamed(
                        'game',
                        pathParameters: {'gameId': active.id},
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Continue Game'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.pushNamed('history'),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('Game History'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.pushNamed('settings'),
                    icon: const Icon(Icons.contrast_rounded),
                    label: const Text('Settings'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Offline by design. No account needed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= 800 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.6;
                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        intro,
                        const SizedBox(height: 32),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: const BoardPreview(),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: intro),
                      const SizedBox(width: 56),
                      const Expanded(child: BoardPreview()),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              const InfoPanel(
                title: 'Your chess space is taking shape',
                message: 'Explore the app and set up a session. The 3D board and offline opponent are not connected yet. Sessions and preferences last until the app closes.',
              ),
            ],
          );
        },
      ),
    );
  }
}
