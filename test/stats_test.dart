import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Simula un teléfono sin datos guardados antes de cada prueba.
    SharedPreferences.setMockInitialValues({});
  });

  group('DayStats', () {
    test('add suma una sesión y los minutos', () {
      final s = const DayStats().add(25).add(25);
      expect(s.sessions, 2);
      expect(s.minutes, 50);
    });

    test('toJson y fromJson son inversos', () {
      const original = DayStats(sessions: 3, minutes: 75);
      final copy = DayStats.fromJson(original.toJson());
      expect(copy.sessions, 3);
      expect(copy.minutes, 75);
    });
  });

  group('StatsRepository', () {
    test('dayKey rellena con ceros', () {
      expect(StatsRepository.dayKey(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('recordSession guarda y load recupera', () async {
      await StatsRepository.recordSession(25);
      await StatsRepository.recordSession(25);
      final data = await StatsRepository.load();
      final today = data[StatsRepository.dayKey(DateTime.now())]!;
      expect(today.sessions, 2);
      expect(today.minutes, 50);
    });

    test('clear borra todo', () async {
      await StatsRepository.recordSession(25);
      await StatsRepository.clear();
      expect(await StatsRepository.load(), isEmpty);
    });
  });
}