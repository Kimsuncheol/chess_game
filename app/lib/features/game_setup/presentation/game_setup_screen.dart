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
  Difficulty _difficulty = Difficulty.balanced;

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
              subtitle: 'Choose your side and the challenge you have in mind.',
            ),
            const SizedBox(height: 32),
            Text('Your side', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in PlayerColor.values)
                  ChoiceChip(
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(color.label),
                    ),
                    selected: _color == color,
                    onSelected: controller.busy
                        ? null
                        : (_) => setState(() => _color = color),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'Opponent strength',
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
              child: Card(
                child: Column(
                  children: [
                    for (final difficulty in Difficulty.values)
                      RadioListTile<Difficulty>(
                        value: difficulty,
                        enabled: !controller.busy,
                        title: Text(difficulty.label),
                        subtitle: Text(difficulty.description),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const InfoPanel(
              title: 'Preview session',
              icon: Icons.view_in_ar_outlined,
              message: 'You can explore the board screen and session controls. Play will be available when the 3D board, rules and opponent are connected.',
            ),
            if (controller.error != null) ErrorNotice(controller.error!),
            const SizedBox(height: 28),
            FilledButton.icon(
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
                controller.busy ? 'Opening session…' : 'Open preview session',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
