import 'package:flutter/foundation.dart';

import '../../../services/storage/local_storage.dart';
import '../domain/app_settings.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository);
  final SettingsRepository _repository;
  AppSettings _settings = const AppSettings();
  bool _saving = false;
  bool _disposed = false;
  String? _error;
  AppSettings get settings => _settings;
  bool get saving => _saving;
  String? get error => _error;

  Future<void> load() async {
    _settings = await _repository.loadSettings();
    if (!_disposed) notifyListeners();
  }

  Future<void> update(AppSettings next) async {
    if (_saving || _disposed) return;
    final previous = _settings;
    _saving = true;
    _error = null;
    _settings = next;
    notifyListeners();
    try {
      await _repository.saveSettings(next);
    } catch (_) {
      if (!_disposed) _settings = previous;
      _error = 'Your preferences could not be saved. Please try again.';
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
