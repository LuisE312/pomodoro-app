import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'pomodoro_phase.dart';
import 'settings.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
String _mmss(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  return '${_two(s ~/ 60)}:${_two(s % 60)}';
}

/// Todo lo relacionado con notificaciones, en un solo lugar.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _runningId = 1; // notificación fija del temporizador
  static const int _endId = 2; // aviso de fin de fase
  static const String _runningChannelId = 'pomodoro_running';

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_timer'),
      ),
    );
  }

  /// Pide permiso de notificaciones (Android 13+). Devuelve si está concedido.
  Future<bool> ensurePermission() async {
    final android = _android;
    if (android == null) return false;
    if (await android.areNotificationsEnabled() ?? false) return true;
    return await android.requestNotificationsPermission() ?? false;
  }

  /// En Android 8+ el sonido y la vibración pertenecen al "canal", y no se
  /// pueden cambiar después de crearlo. Por eso hay un canal por combinación.
  NotificationDetails _endDetails(PomodoroSettings s) {
    final sound = s.soundEnabled;
    final vibration = s.vibrationEnabled;
    final parts = [if (sound) 'sonido', if (vibration) 'vibración'];
    final label = parts.isEmpty ? 'silencioso' : parts.join(' y ');

    return NotificationDetails(
      android: AndroidNotificationDetails(
        'pomodoro_end_s${sound ? 1 : 0}_v${vibration ? 1 : 0}',
        'Fin de fase ($label)',
        channelDescription: 'Avisa cuando termina una fase del temporizador',
        importance: Importance.max,
        priority: Priority.high,
        playSound: sound,
        sound: sound ? const RawResourceAndroidNotificationSound('bell') : null,
        enableVibration: vibration,
        vibrationPattern:
        vibration ? Int64List.fromList([0, 500, 250, 500, 250, 500]) : null,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
      ),
    );
  }

  /// Programa el aviso para el momento exacto en que termina la fase.
  Future<void> scheduleEnd({
    required DateTime endTime,
    required PomodoroPhase endingPhase,
    required PomodoroPhase nextPhase,
    required PomodoroSettings settings,
  }) async {
    try {
      final focusEnding = endingPhase == PomodoroPhase.focus;
      await _plugin.zonedSchedule(
        id: _endId,
        title: focusEnding ? '¡Enfoque terminado!' : 'Descanso terminado',
        body: focusEnding
            ? 'Es hora de: ${nextPhase.label.toLowerCase()}'
            : 'Listo para el siguiente enfoque',
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.UTC,
          endTime.millisecondsSinceEpoch,
        ),
        notificationDetails: _endDetails(settings),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('No se pudo programar el aviso: $e');
    }
  }

  /// Notificación fija con cuenta regresiva que dibuja el propio Android.
  Future<void> showRunning({
    required PomodoroPhase phase,
    required DateTime endTime,
  }) async {
    try {
      final msLeft = endTime.difference(DateTime.now()).inMilliseconds;
      await _plugin.show(
        id: _runningId,
        title: phase.label,
        body: 'En curso · termina a las ${_clock(endTime)}',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _runningChannelId,
            'Temporizador en curso',
            channelDescription: 'Muestra el temporizador mientras está activo',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: true,
            when: endTime.millisecondsSinceEpoch,
            usesChronometer: true,
            chronometerCountDown: true,
            // Se quita sola al terminar, aunque la app esté cerrada.
            timeoutAfter: msLeft > 0 ? msLeft : null,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación: $e');
    }
  }

  Future<void> showPaused({
    required PomodoroPhase phase,
    required Duration remaining,
  }) async {
    try {
      await _plugin.show(
        id: _runningId,
        title: '${phase.label} en pausa',
        body: 'Quedan ${_mmss(remaining)}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _runningChannelId,
            'Temporizador en curso',
            channelDescription: 'Muestra el temporizador mientras está activo',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: false,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación: $e');
    }
  }

  Future<void> cancelRunning() => _plugin.cancel(id: _runningId);
  Future<void> cancelEnd() => _plugin.cancel(id: _endId);
  Future<void> cancelAll() => _plugin.cancelAll();
}