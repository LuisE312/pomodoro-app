import 'package:shared_preferences/shared_preferences.dart';

import 'pomodoro_phase.dart';

enum NotificationStyle {
  full(label: 'Completa', description: 'Muestra colores, detalles y botones de acción'),
  minimal(label: 'Mínima', description: 'Muestra solo la cuenta regresiva');

  const NotificationStyle({required this.label, required this.description});

  final String label;
  final String description;
}

enum AppThemeMode {
  system(label: 'Sistema'),
  light(label: 'Claro'),
  dark(label: 'Oscuro');

  const AppThemeMode({required this.label});
  final String label;
}

enum AlertSound {
  bell(label: 'Campana', rawName: 'bell'),
  chime(label: 'Carillón', rawName: 'chime'),
  beep(label: 'Beep', rawName: 'beep');

  const AlertSound({required this.label, required this.rawName});
  final String label;
  final String rawName;
}

/// Ajustes del usuario. Es inmutable: para cambiar algo se crea una copia.
class PomodoroSettings {
  const PomodoroSettings({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.cyclesBeforeLongBreak = 4,
    this.dailyGoal = 8,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.autoStartNext = false,
    this.notificationStyle = NotificationStyle.full,
    this.themeMode = AppThemeMode.system,
    this.amoledMode = false,
    this.keepScreenOn = false,
    this.alertSound = AlertSound.bell,
    this.dailyReminderEnabled = false,
    this.dailyReminderHour = 9,
    this.dailyReminderMinute = 0,
    this.tags = const ['Trabajo', 'Estudio', 'Lectura'],
    this.selectedTag = 'Trabajo',
  });

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int cyclesBeforeLongBreak;
  final int dailyGoal;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool autoStartNext;
  final NotificationStyle notificationStyle;
  final AppThemeMode themeMode;
  final bool amoledMode;
  final bool keepScreenOn;
  final AlertSound alertSound;
  final bool dailyReminderEnabled;
  final int dailyReminderHour;
  final int dailyReminderMinute;
  final List<String> tags;
  final String? selectedTag;

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
    int? dailyGoal,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? autoStartNext,
    NotificationStyle? notificationStyle,
    AppThemeMode? themeMode,
    bool? amoledMode,
    bool? keepScreenOn,
    AlertSound? alertSound,
    bool? dailyReminderEnabled,
    int? dailyReminderHour,
    int? dailyReminderMinute,
    List<String>? tags,
    Object? selectedTag = _sentinel,
  }) {
    return PomodoroSettings(
      focusMinutes: focusMinutes ?? this.focusMinutes,
      shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      cyclesBeforeLongBreak:
      cyclesBeforeLongBreak ?? this.cyclesBeforeLongBreak,
      dailyGoal: dailyGoal ?? this.dailyGoal,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      autoStartNext: autoStartNext ?? this.autoStartNext,
      notificationStyle: notificationStyle ?? this.notificationStyle,
      themeMode: themeMode ?? this.themeMode,
      amoledMode: amoledMode ?? this.amoledMode,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      alertSound: alertSound ?? this.alertSound,
      dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
      dailyReminderHour: dailyReminderHour ?? this.dailyReminderHour,
      dailyReminderMinute: dailyReminderMinute ?? this.dailyReminderMinute,
      tags: tags ?? this.tags,
      selectedTag: selectedTag == _sentinel
          ? this.selectedTag
          : selectedTag as String?,
    );
  }

  static const _sentinel = Object();

  /// Lee los ajustes guardados; si no hay nada, usa los valores por defecto.
  static Future<PomodoroSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const d = PomodoroSettings();
    final styleIndex = (prefs.getInt('notificationStyle') ?? 0)
        .clamp(0, NotificationStyle.values.length - 1);
    final themeIndex = (prefs.getInt('themeMode') ?? 0)
        .clamp(0, AppThemeMode.values.length - 1);
    final soundIndex = (prefs.getInt('alertSound') ?? 0)
        .clamp(0, AlertSound.values.length - 1);

    final savedTags = prefs.getStringList('tags') ?? d.tags;
    final savedSelectedTag = prefs.getString('selectedTag');

    return PomodoroSettings(
      focusMinutes: prefs.getInt('focusMinutes') ?? d.focusMinutes,
      shortBreakMinutes:
      prefs.getInt('shortBreakMinutes') ?? d.shortBreakMinutes,
      longBreakMinutes: prefs.getInt('longBreakMinutes') ?? d.longBreakMinutes,
      cyclesBeforeLongBreak:
      prefs.getInt('cyclesBeforeLongBreak') ?? d.cyclesBeforeLongBreak,
      dailyGoal: (prefs.getInt('dailyGoal') ?? d.dailyGoal).clamp(1, 16),
      soundEnabled: prefs.getBool('soundEnabled') ?? d.soundEnabled,
      vibrationEnabled: prefs.getBool('vibrationEnabled') ?? d.vibrationEnabled,
      autoStartNext: prefs.getBool('autoStartNext') ?? d.autoStartNext,
      notificationStyle: NotificationStyle.values[styleIndex],
      themeMode: AppThemeMode.values[themeIndex],
      amoledMode: prefs.getBool('amoledMode') ?? d.amoledMode,
      keepScreenOn: prefs.getBool('keepScreenOn') ?? d.keepScreenOn,
      alertSound: AlertSound.values[soundIndex],
      dailyReminderEnabled:
          prefs.getBool('dailyReminderEnabled') ?? d.dailyReminderEnabled,
      dailyReminderHour:
          (prefs.getInt('dailyReminderHour') ?? d.dailyReminderHour).clamp(0, 23),
      dailyReminderMinute:
          (prefs.getInt('dailyReminderMinute') ?? d.dailyReminderMinute).clamp(0, 59),
      tags: savedTags,
      selectedTag: savedSelectedTag ?? (savedTags.isNotEmpty ? savedTags.first : null),
    );
  }

  /// Guarda los ajustes en el teléfono.
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('focusMinutes', focusMinutes);
    await prefs.setInt('shortBreakMinutes', shortBreakMinutes);
    await prefs.setInt('longBreakMinutes', longBreakMinutes);
    await prefs.setInt('cyclesBeforeLongBreak', cyclesBeforeLongBreak);
    await prefs.setInt('dailyGoal', dailyGoal);
    await prefs.setBool('soundEnabled', soundEnabled);
    await prefs.setBool('vibrationEnabled', vibrationEnabled);
    await prefs.setBool('autoStartNext', autoStartNext);
    await prefs.setInt('notificationStyle', notificationStyle.index);
    await prefs.setInt('themeMode', themeMode.index);
    await prefs.setBool('amoledMode', amoledMode);
    await prefs.setBool('keepScreenOn', keepScreenOn);
    await prefs.setInt('alertSound', alertSound.index);
    await prefs.setBool('dailyReminderEnabled', dailyReminderEnabled);
    await prefs.setInt('dailyReminderHour', dailyReminderHour);
    await prefs.setInt('dailyReminderMinute', dailyReminderMinute);
    await prefs.setStringList('tags', tags);
    if (selectedTag != null) {
      await prefs.setString('selectedTag', selectedTag!);
    } else {
      await prefs.remove('selectedTag');
    }
  }
}