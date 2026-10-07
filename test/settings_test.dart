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
    });

    test('copyWith cambia solo lo indicado', () {
      const original = PomodoroSettings();
      final changed = original.copyWith(focusMinutes: 50, soundEnabled: false);
      expect(changed.focusMinutes, 50);
      expect(changed.soundEnabled, false);
      expect(changed.shortBreakMinutes, original.shortBreakMinutes);
      expect(changed.vibrationEnabled, original.vibrationEnabled);
    });
  });
}