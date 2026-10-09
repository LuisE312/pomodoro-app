import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_app/stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Simula un teléfono sin datos guardados antes de cada prueba.
    SharedPreferences.setMockInitialValues({});
  });

  group('SessionRecord', () {
    test('toJson y fromJson son inversos', () {
      final now = DateTime(2026, 4, 10, 14, 30);
      final record = SessionRecord(timestamp: now, minutes: 25, tag: 'Trabajo');
      final copy = SessionRecord.fromJson(record.toJson());

      expect(copy.timestamp, now);
      expect(copy.minutes, 25);
      expect(copy.tag, 'Trabajo');
    });
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

      final sessions = await StatsRepository.loadSessions();
      expect(sessions.length, 2);
      expect(sessions.first.minutes, 25);
    });

    test('migración automática de stats_v1 a sessions_v2', () async {
      final prefs = await SharedPreferences.getInstance();
      final v1Data = {
        '2026-04-01': const DayStats(sessions: 2, minutes: 50).toJson(),
      };
      await prefs.setString('stats_v1', jsonEncode(v1Data));

      final sessions = await StatsRepository.loadSessions();
      expect(sessions.length, 2);
      expect(sessions.first.timestamp.year, 2026);
      expect(sessions.first.timestamp.month, 4);
      expect(sessions.first.timestamp.day, 1);
      expect(sessions.first.minutes, 25);

      final map = await StatsRepository.load();
      expect(map['2026-04-01']?.sessions, 2);
      expect(map['2026-04-01']?.minutes, 50);
    });

    test('clear borra todo', () async {
      await StatsRepository.recordSession(25);
      await StatsRepository.clear();
      expect(await StatsRepository.load(), isEmpty);
      expect(await StatsRepository.loadSessions(), isEmpty);
    });

    test('calculateStreak calcula racha consecutiva de días activos', () {
      final now = DateTime(2026, 4, 10);
      final data = <String, DayStats>{
        '2026-04-10': const DayStats(sessions: 2, minutes: 50),
        '2026-04-09': const DayStats(sessions: 1, minutes: 25),
        '2026-04-08': const DayStats(sessions: 3, minutes: 75),
        '2026-04-06': const DayStats(sessions: 1, minutes: 25), // Saltó el día 07
      };

      expect(StatsRepository.calculateStreak(data, now), 3);
    });

    test('calculateBestStreak encuentra la mayor racha histórica', () {
      final data = <String, DayStats>{
        '2026-04-01': const DayStats(sessions: 1, minutes: 25),
        '2026-04-02': const DayStats(sessions: 1, minutes: 25),
        '2026-04-03': const DayStats(sessions: 1, minutes: 25), // Racha de 3
        '2026-04-05': const DayStats(sessions: 1, minutes: 25), // Brecha el 04
        '2026-04-06': const DayStats(sessions: 1, minutes: 25), // Racha de 2
      };

      expect(StatsRepository.calculateBestStreak(data), 3);
    });

    test('getBestDay identifica el día con más minutos', () {
      final data = <String, DayStats>{
        '2026-04-01': const DayStats(sessions: 1, minutes: 25),
        '2026-04-02': const DayStats(sessions: 4, minutes: 100),
        '2026-04-03': const DayStats(sessions: 2, minutes: 50),
      };

      final best = StatsRepository.getBestDay(data);
      expect(best?.key, '2026-04-02');
      expect(best?.value.minutes, 100);
    });

    test('getMostProductiveTimeSlot identifica la franja preferida', () {
      final sessions = [
        SessionRecord(timestamp: DateTime(2026, 4, 1, 9, 0), minutes: 25),
        SessionRecord(timestamp: DateTime(2026, 4, 1, 10, 0), minutes: 25),
        SessionRecord(timestamp: DateTime(2026, 4, 1, 15, 0), minutes: 25),
      ];

      expect(StatsRepository.getMostProductiveTimeSlot(sessions), 'Mañana (06-12h)');
    });

    test('exportar e importar JSON y CSV funcionan correctamente', () async {
      await StatsRepository.recordSession(25, tag: 'Trabajo');

      final jsonStr = await StatsRepository.exportJson();
      expect(jsonStr, contains('Trabajo'));

      await StatsRepository.clear();
      expect(await StatsRepository.loadSessions(), isEmpty);

      await StatsRepository.importJson(jsonStr);
      var sessions = await StatsRepository.loadSessions();
      expect(sessions.length, 1);
      expect(sessions.first.tag, 'Trabajo');
      expect(sessions.first.minutes, 25);

      final csvStr = await StatsRepository.exportCsv();
      expect(csvStr, contains('Trabajo'));

      await StatsRepository.clear();
      await StatsRepository.importCsv(csvStr);
      sessions = await StatsRepository.loadSessions();
      expect(sessions.length, 1);
      expect(sessions.first.minutes, 25);
    });
  });
}