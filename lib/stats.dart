import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Registro individual de una sesión de enfoque completada.
class SessionRecord {
  const SessionRecord({
    required this.timestamp,
    required this.minutes,
    this.tag,
    this.note,
  });

  final DateTime timestamp;
  final int minutes;
  final String? tag;

  /// Nota opcional de una línea ("¿en qué trabajaste?").
  final String? note;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'minutes': minutes,
        if (tag != null) 'tag': tag,
        if (note != null) 'note': note,
      };

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        timestamp: DateTime.parse(json['timestamp'] as String),
        minutes: json['minutes'] as int? ?? 0,
        tag: json['tag'] as String?,
        note: json['note'] as String?,
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

  /// Agrupa sesiones por día.
  static Map<String, DayStats> _groupByDay(List<SessionRecord> sessions) {
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

  /// Carga las estadísticas agrupadas por día (mantiene compatibilidad total).
  static Future<Map<String, DayStats>> load() async {
    return _groupByDay(await loadSessions());
  }

  /// Guarda la lista completa (v2) y mantiene v1 sincronizado por compatibilidad.
  static Future<void> _save(
    SharedPreferences prefs,
    List<SessionRecord> sessions,
  ) async {
    await prefs.setString(
      _keyV2,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
    await prefs.setBool(_keyMigrated, true);
    await prefs.setString(
      _keyV1,
      jsonEncode(
        _groupByDay(sessions).map((k, v) => MapEntry(k, v.toJson())),
      ),
    );
  }

  /// Registra una sesión de enfoque completada en `sessions_v2`.
  ///
  /// [at] es el momento en que terminó la sesión (por defecto, ahora). Importa
  /// cuando la app estaba cerrada: así la sesión cae en su día y hora reales.
  static Future<void> recordSession(
    int minutes, {
    String? tag,
    DateTime? at,
    String? note,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);

    final sessions = await loadSessions();
    sessions.add(
      SessionRecord(
        timestamp: at ?? DateTime.now(),
        minutes: minutes,
        tag: tag,
        note: _cleanNote(note),
      ),
    );
    await _save(prefs, sessions);
  }

  /// Deja la nota en una sola línea y sin espacios sobrantes (null si queda vacía).
  static String? _cleanNote(String? note) {
    if (note == null) return null;
    final text = note.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return text.isEmpty ? null : text;
  }

  static bool _same(SessionRecord a, SessionRecord b) =>
      a.timestamp == b.timestamp && a.minutes == b.minutes && a.tag == b.tag;

  /// Añade una sesión a mano (por ejemplo, una que olvidaste registrar).
  static Future<void> addSession(SessionRecord session) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);
    final sessions = await loadSessions();
    sessions.add(
      SessionRecord(
        timestamp: session.timestamp,
        minutes: session.minutes,
        tag: session.tag,
        note: _cleanNote(session.note),
      ),
    );
    sessions.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    await _save(prefs, sessions);
  }

  /// Sustituye [original] por [updated]. Devuelve false si no la encuentra.
  static Future<bool> updateSession(
    SessionRecord original,
    SessionRecord updated,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);
    final sessions = await loadSessions();
    final index = sessions.indexWhere((s) => _same(s, original));
    if (index < 0) return false;
    sessions[index] = SessionRecord(
      timestamp: updated.timestamp,
      minutes: updated.minutes,
      tag: updated.tag,
      note: _cleanNote(updated.note),
    );
    sessions.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    await _save(prefs, sessions);
    return true;
  }

  /// Borra una sesión. Devuelve false si no la encuentra.
  static Future<bool> deleteSession(SessionRecord session) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);
    final sessions = await loadSessions();
    final index = sessions.indexWhere((s) => _same(s, session));
    if (index < 0) return false;
    sessions.removeAt(index);
    await _save(prefs, sessions);
    return true;
  }

  /// Pone (o quita, si queda vacía) la nota de la sesión que terminó en [timestamp].
  static Future<bool> setNote(DateTime timestamp, String? note) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);
    final sessions = await loadSessions();
    final index = sessions.indexWhere((s) => s.timestamp == timestamp);
    if (index < 0) return false;
    final s = sessions[index];
    sessions[index] = SessionRecord(
      timestamp: s.timestamp,
      minutes: s.minutes,
      tag: s.tag,
      note: _cleanNote(note),
    );
    await _save(prefs, sessions);
    return true;
  }

  /// Cambia el nombre de una etiqueta también en el historial, para que las
  /// estadísticas no pierdan las sesiones antiguas.
  static Future<void> renameTag(String oldName, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);
    final sessions = await loadSessions();
    var changed = false;
    final updated = <SessionRecord>[];
    for (final s in sessions) {
      if (s.tag == oldName) {
        changed = true;
        updated.add(
          SessionRecord(
            timestamp: s.timestamp,
            minutes: s.minutes,
            tag: newName,
            note: s.note,
          ),
        );
      } else {
        updated.add(s);
      }
    }
    if (changed) await _save(prefs, updated);
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
    buffer.writeln('timestamp,minutes,tag,note');
    String esc(String? v) => v == null ? '' : '"${v.replaceAll('"', '""')}"';
    for (final s in sessions) {
      buffer.writeln(
        '${s.timestamp.toIso8601String()},${s.minutes},${esc(s.tag)},${esc(s.note)}',
      );
    }
    return buffer.toString();
  }

  /// Clave para detectar sesiones repetidas al combinar.
  static String _sessionKey(SessionRecord s) =>
      '${s.timestamp.toIso8601String()}|${s.minutes}|${s.tag ?? ''}';

  /// Guarda las sesiones importadas. Con [replace] false se combinan con las
  /// existentes sin duplicar las que ya estaban; con true sustituyen todo.
  /// Devuelve cuántas se añadieron y cuántas se omitieron (repetidas o no
  /// válidas). Si el archivo no trae ninguna sesión válida lanza
  /// [FormatException] y no toca nada, para no vaciar el historial por error.
  static Future<({int added, int skipped})> _applyImport(
    List<SessionRecord> incoming,
    int invalid, {
    required bool replace,
  }) async {
    if (incoming.isEmpty) {
      throw const FormatException(
        'El archivo no contiene sesiones válidas.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);

    final base = replace ? <SessionRecord>[] : await loadSessions();
    final seen = base.map(_sessionKey).toSet();
    var added = 0;
    var skipped = invalid;
    for (final s in incoming) {
      if (seen.add(_sessionKey(s))) {
        base.add(s);
        added++;
      } else {
        skipped++;
      }
    }
    base.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    await _save(prefs, base);
    return (added: added, skipped: skipped);
  }

  /// Importa el historial de sesiones desde una cadena JSON.
  static Future<({int added, int skipped})> importJson(
    String jsonString, {
    bool replace = false,
  }) async {
    final decoded = jsonDecode(jsonString) as List<dynamic>;
    final incoming = <SessionRecord>[];
    var invalid = 0;
    for (final e in decoded) {
      try {
        final r = SessionRecord.fromJson(e as Map<String, dynamic>);
        if (r.minutes > 0) {
          incoming.add(r);
        } else {
          invalid++;
        }
      } catch (_) {
        invalid++;
      }
    }
    return _applyImport(incoming, invalid, replace: replace);
  }

  /// Parte una línea CSV respetando las comillas ("a,b" es un solo campo).
  static List<String> _splitCsvLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    fields.add(buf.toString());
    return fields;
  }

  /// Importa el historial de sesiones desde una cadena CSV. Las filas con
  /// fecha o minutos inválidos se omiten (antes se convertían en "ahora"/25).
  static Future<({int added, int skipped})> importCsv(
    String csvString, {
    bool replace = false,
  }) async {
    final lines = csvString.split(RegExp(r'\r?\n'));
    final incoming = <SessionRecord>[];
    var invalid = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (i == 0 && line.toLowerCase().startsWith('timestamp')) continue;
      final parts = _splitCsvLine(line);
      final timestamp =
          parts.isNotEmpty ? DateTime.tryParse(parts[0].trim()) : null;
      final minutes = parts.length >= 2 ? int.tryParse(parts[1].trim()) : null;
      if (timestamp == null || minutes == null || minutes <= 0) {
        invalid++;
        continue;
      }
      String? tag;
      if (parts.length >= 3) {
        tag = parts[2].trim();
        if (tag.isEmpty) tag = null;
      }
      String? note;
      if (parts.length >= 4) {
        note = _cleanNote(parts.sublist(3).join(','));
      }
      incoming.add(
        SessionRecord(timestamp: timestamp, minutes: minutes, tag: tag, note: note),
      );
    }
    return _applyImport(incoming, invalid, replace: replace);
  }
}
