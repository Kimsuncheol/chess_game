import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';
import '../domain/app_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).settings;
    return PageLayout(
      title: 'Settings',
      maxWidth: 720,
      child: ListenableBuilder(
        listenable: controller,
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
                  if (value != null) {
                    controller.update(settings.copyWith(appearance: value));
                  }
                },
                child: Card(
                  child: Column(
                    children: [
                      for (final mode in Appearance.values)
                        RadioListTile<Appearance>(
                          value: mode,
                          enabled: !controller.saving,
                          title: Text(mode.label),
                          subtitle: Text(mode.description),
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
                      title: const Text('Sound effects'),
                      subtitle: const Text(
                        'Preference for the future 3D board',
                      ),
                      value: settings.soundEnabled,
                      onChanged: controller.saving
                          ? null
                          : (value) => controller.update(
                              settings.copyWith(soundEnabled: value),
                            ),
                    ),
                    SwitchListTile(
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
              if (controller.error != null) ErrorNotice(controller.error!),
              const SizedBox(height: 24),
              const InfoPanel(
                title: 'On this device, for this visit',
                icon: Icons.phonelink_lock_rounded,
                message: 'No account or cloud connection. Preferences and sessions currently reset when the app closes.',
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'Still Chess',
                  applicationVersion: '0.1.0',
                ),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Open-source licenses'),
              ),
            ],
          );
        },
      ),
    );
  }
}
