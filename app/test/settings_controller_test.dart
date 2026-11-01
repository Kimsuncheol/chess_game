import 'package:chess_game/features/settings/application/settings_controller.dart';
import 'package:chess_game/features/settings/domain/app_settings.dart';
import 'package:chess_game/services/storage/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> loadSettings() async => const AppSettings();
  @override
  Future<void> saveSettings(AppSettings settings) async =>
      throw StateError('Disk full');
}

void main() {
  test(
    'save failure retains committed preferences and exposes retryable error',
    () async {
      final controller = SettingsController(FailingSettingsRepository());
      addTearDown(controller.dispose);
      await controller.load();
      await controller.update(const AppSettings(appearance: Appearance.dark));
      expect(controller.settings.appearance, Appearance.system);
      expect(controller.error, isNotNull);
      expect(controller.saving, isFalse);
    },
  );
}
