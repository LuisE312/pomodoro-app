import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Registro individual de una sesión de enfoque completada.
class SessionRecord {
  const SessionRecord({
    required this.timestamp,
    required this.minutes,
    this.tag,
  });

  final DateTime timestamp;
  final int minutes;
  final String? tag;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'minutes': minutes,
        if (tag != null) 'tag': tag,
      };

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        timestamp: DateTime.parse(json['timestamp'] as String),
        minutes: json['minutes'] as int? ?? 0,
        tag: json['tag'] as String?,
      );
}

/// Resumen de un día: cuántas sesiones de enfoque y cuántos minutos.
class DayStats {
  const DayStats({this.sessions = 0, this.minutes = 0});

  final int sessions;
  final int minutes;

  /// Devuelve una copia con una sesión más.
  DayStats add(int addedMinutes) =>
      DayStats(sessions: sessions + 1, minutes: minutes + addedMinutes);

  Map<String, dynamic> toJson() => {'sessions': sessions, 'minutes': minutes};

  factory DayStats.fromJson(Map<String, dynamic> json) => DayStats(
        sessions: json['sessions'] as int? ?? 0,
        minutes: json['minutes'] as int? ?? 0,
      );
}

/// Guarda y lee las estadísticas del teléfono.
class StatsRepository {
  static const _keyV1 = 'stats_v1';
  static const _keyV2 = 'sessions_v2';
  static const _keyMigrated = 'sessions_migrated_v1_v2';

  /// Convierte una fecha en texto "aaaa-mm-dd" para usarla como clave.
  static String dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Garantiza que los registros antiguos de `stats_v1` se migren a `sessions_v2` una sola vez.
  static Future<void> _ensureMigrated(SharedPreferences prefs) async {
    final isMigrated = prefs.getBool(_keyMigrated) ?? false;
    if (isMigrated) return;

    final rawV1 = prefs.getString(_keyV1);
    final rawV2 = prefs.getString(_keyV2);

    List<SessionRecord> sessions = [];
    if (rawV2 != null) {
      try {
        final decoded = jsonDecode(rawV2) as List<dynamic>;
        sessions = decoded
            .map((e) => SessionRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    if (rawV1 != null) {
      try {
        final decodedV1 = jsonDecode(rawV1) as Map<String, dynamic>;
        decodedV1.forEach((dayStr, value) {
          final dayJson = value as Map<String, dynamic>;
          final dayStats = DayStats.fromJson(dayJson);
          final parts = dayStr.split('-');
          if (parts.length == 3 && dayStats.sessions > 0) {
            final year = int.parse(parts[0]);
            final month = int.parse(parts[1]);
            final day = int.parse(parts[2]);
            final sessionMinutes = (dayStats.minutes / dayStats.sessions).round();

            for (var i = 0; i < dayStats.sessions; i++) {
              final timestamp = DateTime(year, month, day, 12, 0)
                  .add(Duration(minutes: i * 30));
              sessions.add(
                SessionRecord(timestamp: timestamp, minutes: sessionMinutes),
              );
            }
          }
        });
      } catch (_) {}
    }

    await prefs.setString(
      _keyV2,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
    await prefs.setBool(_keyMigrated, true);
  }

  /// Carga todas las sesiones detalladas registradas (`sessions_v2`).
  static Future<List<SessionRecord>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);

    final rawV2 = prefs.getString(_keyV2);
    if (rawV2 == null) return [];
    try {
      final decoded = jsonDecode(rawV2) as List<dynamic>;
      return decoded
          .map((e) => SessionRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Carga las estadísticas agrupadas por día (mantiene compatibilidad total).
  static Future<Map<String, DayStats>> load() async {
    final sessions = await loadSessions();
    final Map<String, DayStats> map = {};

    for (final s in sessions) {
      final key = dayKey(s.timestamp);
      final current = map[key] ?? const DayStats();
      map[key] = DayStats(
        sessions: current.sessions + 1,
        minutes: current.minutes + s.minutes,
      );
    }

    return map;
  }

  /// Registra una sesión de enfoque completada hoy en `sessions_v2`.
  static Future<void> recordSession(int minutes, {String? tag}) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);

    final sessions = await loadSessions();
    sessions.add(
      SessionRecord(
        timestamp: DateTime.now(),
        minutes: minutes,
        tag: tag,
      ),
    );

    await prefs.setString(
      _keyV2,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );

    // Mantiene v1 sincronizado por compatibilidad retroactiva
    final allV1 = await load();
    await prefs.setString(
      _keyV1,
      jsonEncode(allV1.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Borra todas las estadísticas guardadas.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyV1);
    await prefs.remove(_keyV2);
    await prefs.remove(_keyMigrated);
  }

  /// Calcula la racha actual de días consecutivos con al menos una sesión.
  static int calculateStreak(Map<String, DayStats> data, [DateTime? relativeTo]) {
    final now = relativeTo ?? DateTime.now();
    final todayKey = dayKey(now);
    final todayStats = data[todayKey];

    var streak = 0;
    var checkDate = now;

    if (todayStats != null && todayStats.sessions > 0) {
      streak++;
      checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day - 1);
    } else {
      // Si hoy aún no hay sesiones, comprobamos si la racha venía de ayer.
      checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day - 1);
    }

    while (true) {
      final key = dayKey(checkDate);
      final stats = data[key];
      if (stats != null && stats.sessions > 0) {
        streak++;
        checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day - 1);
      } else {
        break;
      }
    }

    return streak;
  }

  /// Calcula la mejor racha histórica de días consecutivos.
  static int calculateBestStreak(Map<String, DayStats> data) {
    if (data.isEmpty) return 0;

    final dates = data.entries
        .where((e) => e.value.sessions > 0)
        .map((e) => e.key)
        .toList()
      ..sort();

    if (dates.isEmpty) return 0;

    var maxStreak = 1;
    var currentStreak = 1;

    for (var i = 1; i < dates.length; i++) {
      final prevParts = dates[i - 1].split('-');
      final currParts = dates[i].split('-');

      final prevDate = DateTime(
        int.parse(prevParts[0]),
        int.parse(prevParts[1]),
        int.parse(prevParts[2]),
      );
      final currDate = DateTime(
        int.parse(currParts[0]),
        int.parse(currParts[1]),
        int.parse(currParts[2]),
      );

      final diff = currDate.difference(prevDate).inDays;
      if (diff == 1) {
        currentStreak++;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
      } else if (diff > 1) {
        currentStreak = 1;
      }
    }

    return maxStreak;
  }

  /// Obtiene el mejor día registrado en el historial (con más minutos trabajados).
  static MapEntry<String, DayStats>? getBestDay(Map<String, DayStats> data) {
    if (data.isEmpty) return null;
    MapEntry<String, DayStats>? best;
    for (final entry in data.entries) {
      if (entry.value.sessions > 0) {
        if (best == null || entry.value.minutes > best.value.minutes) {
          best = entry;
        }
      }
    }
    return best;
  }

  /// Determina la franja horaria más productiva basada en las sesiones registradas.
  static String getMostProductiveTimeSlot(List<SessionRecord> sessions) {
    if (sessions.isEmpty) return 'Sin datos';

    final counts = <String, int>{
      'Madrugada (00-06h)': 0,
      'Mañana (06-12h)': 0,
      'Tarde (12-18h)': 0,
      'Noche (18-24h)': 0,
    };

    for (final s in sessions) {
      final hour = s.timestamp.hour;
      if (hour >= 0 && hour < 6) {
        counts['Madrugada (00-06h)'] = counts['Madrugada (00-06h)']! + 1;
      } else if (hour >= 6 && hour < 12) {
        counts['Mañana (06-12h)'] = counts['Mañana (06-12h)']! + 1;
      } else if (hour >= 12 && hour < 18) {
        counts['Tarde (12-18h)'] = counts['Tarde (12-18h)']! + 1;
      } else {
        counts['Noche (18-24h)'] = counts['Noche (18-24h)']! + 1;
      }
    }

    var bestSlot = 'Mañana (06-12h)';
    var maxCount = -1;
    counts.forEach((slot, count) {
      if (count > maxCount) {
        maxCount = count;
        bestSlot = slot;
      }
    });

    return maxCount > 0 ? bestSlot : 'Sin datos';
  }

  /// Exporta todo el historial de sesiones en formato JSON.
  static Future<String> exportJson() async {
    final sessions = await loadSessions();
    return jsonEncode(sessions.map((s) => s.toJson()).toList());
  }

  /// Exporta todo el historial de sesiones en formato CSV.
  static Future<String> exportCsv() async {
    final sessions = await loadSessions();
    final buffer = StringBuffer();
    buffer.writeln('timestamp,minutes,tag');
    for (final s in sessions) {
      final tagEscaped = s.tag != null ? '"${s.tag!.replaceAll('"', '""')}"' : '';
      buffer.writeln('${s.timestamp.toIso8601String()},${s.minutes},$tagEscaped');
    }
    return buffer.toString();
  }

  /// Importa el historial de sesiones desde una cadena JSON.
  static Future<void> importJson(String jsonString) async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(jsonString) as List<dynamic>;
    final sessions = decoded
        .map((e) => SessionRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    await prefs.setString(
      _keyV2,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
    await prefs.setBool(_keyMigrated, true);
    final allV1 = await load();
    await prefs.setString(
      _keyV1,
      jsonEncode(allV1.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Importa el historial de sesiones desde una cadena CSV.
  static Future<void> importCsv(String csvString) async {
    final lines = csvString.split('\n');
    final List<SessionRecord> sessions = [];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      if (parts.length >= 2) {
        final timestamp = DateTime.tryParse(parts[0].replaceAll('"', '')) ?? DateTime.now();
        final minutes = int.tryParse(parts[1].replaceAll('"', '')) ?? 25;
        String? tag;
        if (parts.length >= 3) {
          tag = parts.sublist(2).join(',').replaceAll('"', '').trim();
          if (tag.isEmpty) tag = null;
        }
        sessions.add(SessionRecord(timestamp: timestamp, minutes: minutes, tag: tag));
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyV2,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
    await prefs.setBool(_keyMigrated, true);
    final allV1 = await load();
    await prefs.setString(
      _keyV1,
      jsonEncode(allV1.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}