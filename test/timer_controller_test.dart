import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/pomodoro_phase.dart';
import 'package:pomodoro_app/settings.dart';
import 'package:pomodoro_app/stats.dart';
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

    test('skip avanza a la siguiente fase sin registrar estadísticas de enfoque', () async {
      const settings = PomodoroSettings();
      final controller = await TimerController.load(settings);

      expect(controller.phase, PomodoroPhase.focus);

      // Saltar de Enfoque a Descanso corto
      await controller.skip();
      expect(controller.phase, PomodoroPhase.shortBreak);
      expect(controller.remaining, settings.durationOf(PomodoroPhase.shortBreak));

      // Verificar que NO se registró la sesión en estadísticas
      final stats = await StatsRepository.load();
      expect(stats, isEmpty);

      // Saltar de Descanso corto a Enfoque
      await controller.skip();
      expect(controller.phase, PomodoroPhase.focus);
    });

    test('extend5Min incrementa la duración en 5 minutos', () async {
      const settings = PomodoroSettings(focusMinutes: 25);
      final controller = await TimerController.load(settings);

      await controller.extend5Min();

      expect(controller.total, const Duration(minutes: 30));
      expect(controller.remaining, const Duration(minutes: 30));
    });

    test('applySettings actualiza la duración si la fase está intacta', () async {
      const settings = PomodoroSettings(focusMinutes: 25);
      final controller = await TimerController.load(settings);

      await controller.applySettings(settings.copyWith(focusMinutes: 50));
      expect(controller.total, const Duration(minutes: 50));
      expect(controller.remaining, const Duration(minutes: 50));
    });

    test('sincronización tras paso del tiempo (syncFromClock) avanza fases y registra sesiones', () async {
      const settings = PomodoroSettings(focusMinutes: 25, shortBreakMinutes: 5, autoStartNext: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('timer_phase', 0); // Focus
      await prefs.setBool('timer_running', true);
      await prefs.setInt('timer_initial_ms', const Duration(minutes: 25).inMilliseconds);
      final pastEndMs = DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;
      await prefs.setInt('timer_end_ms', pastEndMs);

      final controller = await TimerController.load(settings);

      // Debería haber completado el enfoque y pasado a descanso corto
      expect(controller.phase, PomodoroPhase.shortBreak);

      final stats = await StatsRepository.load();
      expect(stats, isNotEmpty);
    });

    test('la sesión recuperada con la app cerrada se guarda con su hora real de fin', () async {
      const settings = PomodoroSettings(focusMinutes: 25, shortBreakMinutes: 5, autoStartNext: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('timer_phase', 0);
      await prefs.setBool('timer_running', true);
      await prefs.setInt('timer_initial_ms', const Duration(minutes: 25).inMilliseconds);
      final pastEnd = DateTime.now().subtract(const Duration(minutes: 1));
      await prefs.setInt('timer_end_ms', pastEnd.millisecondsSinceEpoch);

      await TimerController.load(settings);

      final sessions = await StatsRepository.loadSessions();
      expect(sessions.length, 1);
      expect(sessions.single.timestamp.millisecondsSinceEpoch, pastEnd.millisecondsSinceEpoch);
    });

    Future<void> seedFinishedFocus() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('timer_phase', 0);
      await prefs.setBool('timer_running', true);
      await prefs.setInt('timer_initial_ms', const Duration(minutes: 25).inMilliseconds);
      final pastEnd = DateTime.now().subtract(const Duration(minutes: 1));
      await prefs.setInt('timer_end_ms', pastEnd.millisecondsSinceEpoch);
    }

    test('una sesión recuperada emite un evento y anuncia el logro "Primera sesión"', () async {
      const settings = PomodoroSettings(focusMinutes: 25, shortBreakMinutes: 5, autoStartNext: true);
      await seedFinishedFocus();

      final controller = await TimerController.load(settings);

      final event = controller.sessionEvents.value;
      expect(event, isNotNull);
      expect(event!.minutes, 25);
      expect(event.unlocked.map((a) => a.id), contains('first_session'));
    });

    test('los logros que ya tenías no se vuelven a anunciar', () async {
      const settings = PomodoroSettings(focusMinutes: 25, shortBreakMinutes: 5, autoStartNext: true);
      await StatsRepository.recordSession(
        25,
        at: DateTime.now().subtract(const Duration(days: 3)),
      );
      await seedFinishedFocus();

      final controller = await TimerController.load(settings);

      final event = controller.sessionEvents.value;
      expect(event, isNotNull);
      expect(event!.unlocked.map((a) => a.id), isNot(contains('first_session')));
    });

    test('handleNotificationAction: start_next inicia la fase y es idempotente', () async {
      const settings = PomodoroSettings();
      final controller = await TimerController.load(settings);

      await controller.handleNotificationAction('start_next');
      expect(controller.isRunning, true);

      await controller.handleNotificationAction('start_next'); // no debe romper nada
      expect(controller.isRunning, true);

      await controller.handleNotificationAction('pause');
      expect(controller.isRunning, false);
    });
  });
}