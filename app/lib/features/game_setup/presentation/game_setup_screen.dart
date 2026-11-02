import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';
import '../../game/domain/game_session.dart';

class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key});
  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  PlayerColor _color = PlayerColor.white;
  Difficulty _difficulty = Difficulty.intermediate;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).game;
    return PageLayout(
      title: 'Game setup',
      maxWidth: 720,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeading(
              'Set your own pace.',
              subtitle:
                  'Choose your piece color and AI difficulty before starting.',
            ),
            const SizedBox(height: 32),
            Text(
              'Piece color',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            RadioGroup<PlayerColor>(
              groupValue: _color,
              onChanged: (value) {
                if (value != null && !controller.busy) {
                  setState(() => _color = value);
                }
              },
              child: Column(
                children: [
                  for (final color in PlayerColor.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SelectableOptionCard(
                        key: ValueKey('color-option-${color.name}'),
                        selected: _color == color,
                        child: RadioListTile<PlayerColor>(
                          value: color,
                          enabled: !controller.busy,
                          title: Text(color.label),
                          subtitle: Text(color.description),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'AI difficulty',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            RadioGroup<Difficulty>(
              groupValue: _difficulty,
              onChanged: (value) {
                if (value != null && !controller.busy) {
                  setState(() => _difficulty = value);
                }
              },
              child: Column(
                children: [
                  for (final difficulty in Difficulty.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SelectableOptionCard(
                        key: ValueKey('difficulty-option-${difficulty.name}'),
                        selected: _difficulty == difficulty,
                        child: RadioListTile<Difficulty>(
                          value: difficulty,
                          enabled: !controller.busy,
                          title: Text(difficulty.label),
                          subtitle: Text(difficulty.description),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const InfoPanel(
              title: 'Preview session',
              icon: Icons.view_in_ar_outlined,
              message:
                  'You can explore the board screen and session controls. Play will be available when the 3D board and opponent are connected.',
            ),
            if (controller.error != null) ErrorNotice(controller.error!),
            const SizedBox(height: 28),
            FilledButton.icon(
              key: const ValueKey('start-game-button'),
              onPressed: controller.busy
                  ? null
                  : () async {
                      final session = await controller.start(
                        GameConfiguration(
                          color: _color,
                          difficulty: _difficulty,
                        ),
                      );
                      if (!context.mounted || session == null) return;
                      context.replace('/game/${session.id}');
                    },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(
                controller.busy ? 'Starting game…' : 'Start Game',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableOptionCard extends StatelessWidget {
  const _SelectableOptionCard({
    required this.selected,
    required this.child,
    super.key,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: child,
    );
  }
}
