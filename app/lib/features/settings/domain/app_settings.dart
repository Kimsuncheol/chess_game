enum Appearance {
  system('System', 'Follow your device appearance'),
  light('Light', 'A clear, light workspace'),
  dark('Dark', 'A quieter view after hours');

  const Appearance(this.label, this.description);
  final String label;
  final String description;
}

class AppSettings {
  const AppSettings({
    this.appearance = Appearance.system,
    this.soundEnabled = true,
    this.reducedMotion = false,
  });
  final Appearance appearance;
  final bool soundEnabled;
  final bool reducedMotion;

  AppSettings copyWith({
    Appearance? appearance,
    bool? soundEnabled,
    bool? reducedMotion,
  }) => AppSettings(
    appearance: appearance ?? this.appearance,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    reducedMotion: reducedMotion ?? this.reducedMotion,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'appearance': appearance.name,
    'soundEnabled': soundEnabled,
    'reducedMotion': reducedMotion,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final appearance =
        Appearance.values
            .where((mode) => mode.name == json['appearance'])
            .firstOrNull ??
        Appearance.system;
    final soundEnabled = json['soundEnabled'] is bool
        ? json['soundEnabled'] as bool
        : true;
    final reducedMotion = json['reducedMotion'] is bool
        ? json['reducedMotion'] as bool
        : false;
    return AppSettings(
      appearance: appearance,
      soundEnabled: soundEnabled,
      reducedMotion: reducedMotion,
    );
  }
}
