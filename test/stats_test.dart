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

    test('recordSession usa la hora indicada (sesiones con la app cerrada)', () async {
      final end = DateTime(2026, 10, 9, 23, 50);
      await StatsRepository.recordSession(25, at: end);
      final sessions = await StatsRepository.loadSessions();
      expect(sessions.single.timestamp, end);
      expect((await StatsRepository.load())['2026-10-09']?.sessions, 1);
    });

    test('importar combinando no duplica sesiones existentes', () async {
      await StatsRepository.recordSession(25, tag: 'Trabajo', at: DateTime(2026, 10, 1, 10));
      final jsonStr = await StatsRepository.exportJson();
      await StatsRepository.recordSession(30, tag: 'Estudio', at: DateTime(2026, 10, 2, 10));

      final report = await StatsRepository.importJson(jsonStr); // combinar
      expect(report.added, 0);
      expect(report.skipped, 1);
      expect((await StatsRepository.loadSessions()).length, 2);
    });

    test('importar reemplazando deja solo lo del archivo', () async {
      await StatsRepository.recordSession(25, tag: 'Trabajo', at: DateTime(2026, 10, 1, 10));
      final jsonStr = await StatsRepository.exportJson();
      await StatsRepository.recordSession(30, tag: 'Estudio', at: DateTime(2026, 10, 2, 10));

      await StatsRepository.importJson(jsonStr, replace: true);
      expect((await StatsRepository.loadSessions()).length, 1);
    });

    test('un archivo sin sesiones válidas no borra el historial', () async {
      await StatsRepository.recordSession(25, at: DateTime(2026, 10, 1, 10));
      await expectLater(
        StatsRepository.importJson('[]', replace: true),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        StatsRepository.importCsv('timestamp,minutes,tag\nbasura,x,y', replace: true),
        throwsA(isA<FormatException>()),
      );
      expect((await StatsRepository.loadSessions()).length, 1);
    });

    test('CSV: respeta comas entre comillas y omite filas inválidas', () async {
      const csv = 'timestamp,minutes,tag\n'
          '2026-10-01T10:00:00.000,25,"Trabajo, oficina"\n'
          'no-es-fecha,25,Estudio\n'
          '2026-10-02T10:00:00.000,abc,Estudio\n'
          '2026-10-03T10:00:00.000,40,\n';
      final report = await StatsRepository.importCsv(csv);
      expect(report.added, 2);
      expect(report.skipped, 2);
      final sessions = await StatsRepository.loadSessions();
      expect(sessions.first.tag, 'Trabajo, oficina');
      expect(sessions.last.tag, isNull);
    });

    test('renameTag actualiza también el historial', () async {
      await StatsRepository.recordSession(25, tag: 'Trabajo', at: DateTime(2026, 10, 1, 10));
      await StatsRepository.recordSession(25, tag: 'Estudio', at: DateTime(2026, 10, 2, 10));
      await StatsRepository.renameTag('Trabajo', 'Oficina');
      final tags = (await StatsRepository.loadSessions()).map((s) => s.tag).toList();
      expect(tags, ['Oficina', 'Estudio']);
    });

    test('las notas se limpian y viajan en JSON y CSV', () async {
      await StatsRepository.recordSession(
        25,
        tag: 'Trabajo',
        at: DateTime(2026, 10, 1, 10),
        note: '  Informe, "versión 2"\nfinal ',
      );
      const expected = 'Informe, "versión 2" final';
      expect((await StatsRepository.loadSessions()).single.note, expected);

      final jsonStr = await StatsRepository.exportJson();
      final csvStr = await StatsRepository.exportCsv();

      await StatsRepository.clear();
      await StatsRepository.importJson(jsonStr);
      expect((await StatsRepository.loadSessions()).single.note, expected);

      await StatsRepository.clear();
      await StatsRepository.importCsv(csvStr);
      expect((await StatsRepository.loadSessions()).single.note, expected);
    });

    test('editar, añadir y borrar sesiones', () async {
      final a = DateTime(2026, 10, 1, 10);
      await StatsRepository.recordSession(25, tag: 'Trabajo', at: a);
      final original = (await StatsRepository.loadSessions()).single;

      final updated = await StatsRepository.updateSession(
        original,
        SessionRecord(timestamp: a, minutes: 40, tag: 'Estudio', note: 'Mates'),
      );
      expect(updated, true);
      var list = await StatsRepository.loadSessions();
      expect(list.single.minutes, 40);
      expect(list.single.tag, 'Estudio');
      expect(list.single.note, 'Mates');

      await StatsRepository.addSession(
        SessionRecord(timestamp: DateTime(2026, 10, 2, 9), minutes: 30),
      );
      expect((await StatsRepository.loadSessions()).length, 2);

      expect(await StatsRepository.deleteSession(list.single), true);
      list = await StatsRepository.loadSessions();
      expect(list.single.minutes, 30);
      expect(await StatsRepository.deleteSession(original), false);
    });

    test('setNote pone y quita la nota; renameTag la conserva', () async {
      final a = DateTime(2026, 10, 1, 10);
      await StatsRepository.recordSession(25, tag: 'Trabajo', at: a);
      expect(await StatsRepository.setNote(a, 'Informe'), true);

      await StatsRepository.renameTag('Trabajo', 'Oficina');
      var s = (await StatsRepository.loadSessions()).single;
      expect(s.tag, 'Oficina');
      expect(s.note, 'Informe');

      await StatsRepository.setNote(a, '   ');
      s = (await StatsRepository.loadSessions()).single;
      expect(s.note, isNull);
      expect(await StatsRepository.setNote(DateTime(2000), 'x'), false);
    });
  });
}