import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/pomodoro_phase.dart';
import 'package:pomodoro_app/settings.dart';
import 'package:pomodoro_app/timer_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TimerController', () {
    test('se inicializa en fase de enfoque', () async {
      const settings = PomodoroSettings();
      final controller = await TimerController.load(settings);
      expect(controller.phase, PomodoroPhase.focus);
      expect(controller.isRunning, false);
      expect(controller.remaining, settings.durationOf(PomodoroPhase.focus));
    });

    test('start e inician el temporizador', () async {
      const settings = PomodoroSettings();
      final controller = await TimerController.load(settings);

      await controller.start();
      expect(controller.isRunning, true);

      await controller.pause();
      expect(controller.isRunning, false);
    });

    test('reset restaura el estado de la fase actual', () async {
      const settings = PomodoroSettings();
      final controller = await TimerController.load(settings);

      await controller.start();
      await controller.reset();

      expect(controller.isRunning, false);
      expect(controller.remaining, settings.durationOf(PomodoroPhase.focus));
    });

    test('skip avanza a la siguiente fase', () async {
      const settings = PomodoroSettings();
      final controller = await TimerController.load(settings);

      expect(controller.phase, PomodoroPhase.focus);

      // Saltar de Enfoque a Descanso corto
      await controller.skip();
      expect(controller.phase, PomodoroPhase.shortBreak);
      expect(controller.remaining, settings.durationOf(PomodoroPhase.shortBreak));

      // Saltar de Descanso corto a Enfoque
      await controller.skip();
      expect(controller.phase, PomodoroPhase.focus);
    });

    test('ciclo completo de enfoques activa el descanso largo', () async {
      const settings = PomodoroSettings(cyclesBeforeLongBreak: 2);
      final controller = await TimerController.load(settings);

      // Enfoque 1
      await controller.skip();
      expect(controller.phase, PomodoroPhase.shortBreak);

      // Descanso corto
      await controller.skip();
      expect(controller.phase, PomodoroPhase.focus);

      // Enfoque 2 (alcanza el límite de 2 ciclos)
      await controller.skip();
      expect(controller.phase, PomodoroPhase.longBreak);
    });
  });
}