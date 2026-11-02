import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';
import '../domain/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _cameraResetConfirmed = false;

  Future<void> _handleResetCamera() async {
    final gameController = AppScope.of(context).game;
    await gameController.resetCamera();
    if (!mounted) return;
    setState(() {
      _cameraResetConfirmed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.of(context);
    final controller = dependencies.settings;
    final gameController = dependencies.game;
    return PageLayout(
      title: 'Settings',
      maxWidth: 720,
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, gameController]),
        builder: (context, _) {
          final settings = controller.settings;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeading(
                'Make yourself comfortable.',
                subtitle: 'Small preferences for a more thoughtful game.',
              ),
              const SizedBox(height: 32),
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              RadioGroup<Appearance>(
                groupValue: settings.appearance,
                onChanged: (value) {
                  if (value != null && !controller.saving) {
                    controller.update(settings.copyWith(appearance: value));
                  }
                },
                child: Card(
                  child: Column(
                    children: [
                      for (final mode in Appearance.values)
                        RadioListTile<Appearance>(
                          key: ValueKey('appearance-option-${mode.name}'),
                          value: mode,
                          enabled: !controller.saving,
                          title: Text(
                            mode == Appearance.system
                                ? 'System Default'
                                : mode.label,
                          ),
                          subtitle: Text(mode.description),
                          secondary: mode == Appearance.system
                              ? Text(
                                  'System',
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Game experience',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const ValueKey('sound-effects-switch'),
                      title: const Text('Sound effects'),
                      subtitle: Text(
                        settings.soundEnabled
                            ? 'On · Audio enabled when the 3D game scene is ready'
                            : 'Off · Muted on the 3D board',
                      ),
                      value: settings.soundEnabled,
                      onChanged: controller.saving
                          ? null
                          : (value) => controller.update(
                              settings.copyWith(soundEnabled: value),
                            ),
                    ),
                    SwitchListTile(
                      key: const ValueKey('reduce-motion-switch'),
                      title: const Text('Reduce motion'),
                      subtitle: const Text(
                        'Use immediate transitions. Device accessibility preferences are always respected.',
                      ),
                      value: settings.reducedMotion,
                      onChanged: controller.saving
                          ? null
                          : (value) => controller.update(
                              settings.copyWith(reducedMotion: value),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                '3D board camera',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Default board perspective',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Return the 3D board orbit, pan, and zoom to the default player perspective. Applied immediately or when the game scene is ready.',
                        style: TextStyle(
                          height: 1.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_cameraResetConfirmed) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '3D camera reset has been applied for the board.',
                          key: ValueKey('camera-reset-confirmation'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const ValueKey('settings-reset-camera-button'),
                        onPressed: _handleResetCamera,
                        icon: const Icon(Icons.center_focus_strong_rounded),
                        label: const Text('Reset 3D camera'),
                      ),
                    ],
                  ),
                ),
              ),
              if (controller.error != null) ErrorNotice(controller.error!),
              if (gameController.error != null)
                ErrorNotice(gameController.error!),
              const SizedBox(height: 28),
              Text(
                'Open-source notices',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Card(
                key: const ValueKey('open-source-notices-card'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Still Chess is built with open-source software:',
                      ),
                      const SizedBox(height: 12),
                      const Text('• bishop 1.4.4 — MIT License (chess rules)'),
                      const SizedBox(height: 4),
                      const Text(
                        '• go_router — BSD-3-Clause License (navigation)',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '• Flutter & Dart SDK — BSD-3-Clause License (UI & runtime)',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const ValueKey('open-source-licenses-button'),
                        onPressed: () => showLicensePage(
                          context: context,
                          applicationName: 'Still Chess',
                          applicationVersion: '0.1.0',
                        ),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Open-source licenses'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const InfoPanel(
                title: 'Saved on this device',
                icon: Icons.phonelink_lock_rounded,
                message:
                    'No account or cloud connection. Your preferences and game history are stored locally on this device.',
              ),
            ],
          );
        },
      ),
    );
  }
}
