import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/pomodoro_phase.dart';
import 'package:pomodoro_app/settings.dart';

void main() {
  group('PomodoroSettings', () {
    test('tiene los valores por defecto esperados', () {
      const s = PomodoroSettings();
      expect(s.durationOf(PomodoroPhase.focus), const Duration(minutes: 25));
      expect(
        s.durationOf(PomodoroPhase.shortBreak),
        const Duration(minutes: 5),
      );
      expect(
        s.durationOf(PomodoroPhase.longBreak),
        const Duration(minutes: 15),
      );
      expect(s.cyclesBeforeLongBreak, 4);
      expect(s.dailyGoal, 8);
      expect(s.autoStartNext, false);
      expect(s.themeMode, AppThemeMode.system);
      expect(s.amoledMode, false);
      expect(s.keepScreenOn, false);
    });

    test('copyWith cambia solo lo indicado', () {
      const original = PomodoroSettings();
      final changed = original.copyWith(
        focusMinutes: 50,
        dailyGoal: 10,
        soundEnabled: false,
        autoStartNext: true,
        themeMode: AppThemeMode.dark,
        amoledMode: true,
        keepScreenOn: true,
      );
      expect(changed.focusMinutes, 50);
      expect(changed.dailyGoal, 10);
      expect(changed.soundEnabled, false);
      expect(changed.autoStartNext, true);
      expect(changed.themeMode, AppThemeMode.dark);
      expect(changed.amoledMode, true);
      expect(changed.keepScreenOn, true);
      expect(changed.shortBreakMinutes, original.shortBreakMinutes);
      expect(changed.vibrationEnabled, original.vibrationEnabled);
    });
  });
}