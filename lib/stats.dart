import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
/// Se almacenan como un mapa: { "2026-10-07": {sessions: 3, minutes: 75} }
class StatsRepository {
  static const _key = 'stats_v1';

  /// Convierte una fecha en texto "aaaa-mm-dd" para usarla como clave.
  static String dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Future<Map<String, DayStats>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
            (k, v) => MapEntry(k, DayStats.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      // Si los datos estuvieran dañados, empezamos de cero en vez de fallar.
      return {};
    }
  }

  /// Registra una sesión de enfoque completada hoy.
  static Future<void> recordSession(int minutes) async {
    final all = await load();
    final key = dayKey(DateTime.now());
    all[key] = (all[key] ?? const DayStats()).add(minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}