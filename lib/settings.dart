import 'package:shared_preferences/shared_preferences.dart';

import 'pomodoro_phase.dart';

/// Ajustes del usuario. Es inmutable: para cambiar algo se crea una copia.
class PomodoroSettings {
  const PomodoroSettings({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.cyclesBeforeLongBreak = 4,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int cyclesBeforeLongBreak;
  final bool soundEnabled;
  final bool vibrationEnabled;

  /// Duración de cada fase según los ajustes actuales.
  Duration durationOf(PomodoroPhase phase) => switch (phase) {
    PomodoroPhase.focus => Duration(minutes: focusMinutes),
    PomodoroPhase.shortBreak => Duration(minutes: shortBreakMinutes),
    PomodoroPhase.longBreak => Duration(minutes: longBreakMinutes),
  };

  PomodoroSettings copyWith({
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? cyclesBeforeLongBreak,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) {
    return PomodoroSettings(
      focusMinutes: focusMinutes ?? this.focusMinutes,
      shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      cyclesBeforeLongBreak:
      cyclesBeforeLongBreak ?? this.cyclesBeforeLongBreak,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    );
  }

  /// Lee los ajustes guardados; si no hay nada, usa los valores por defecto.
  static Future<PomodoroSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const d = PomodoroSettings();
    return PomodoroSettings(
      focusMinutes: prefs.getInt('focusMinutes') ?? d.focusMinutes,
      shortBreakMinutes:
      prefs.getInt('shortBreakMinutes') ?? d.shortBreakMinutes,
      longBreakMinutes: prefs.getInt('longBreakMinutes') ?? d.longBreakMinutes,
      cyclesBeforeLongBreak:
      prefs.getInt('cyclesBeforeLongBreak') ?? d.cyclesBeforeLongBreak,
      soundEnabled: prefs.getBool('soundEnabled') ?? d.soundEnabled,
      vibrationEnabled: prefs.getBool('vibrationEnabled') ?? d.vibrationEnabled,
    );
  }

  /// Guarda los ajustes en el teléfono.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('focusMinutes', focusMinutes);
    await prefs.setInt('shortBreakMinutes', shortBreakMinutes);
    await prefs.setInt('longBreakMinutes', longBreakMinutes);
    await prefs.setInt('cyclesBeforeLongBreak', cyclesBeforeLongBreak);
    await prefs.setBool('soundEnabled', soundEnabled);
    await prefs.setBool('vibrationEnabled', vibrationEnabled);
  }
}