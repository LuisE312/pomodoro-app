import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'pomodoro_phase.dart';
import 'settings.dart';
import 'timer_engine.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
String _mmss(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  return '${_two(s ~/ 60)}:${_two(s % 60)}';
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final actionId = response.actionId;
  if (actionId == 'pause') {
    unawaited(TimerEngine.pause());
  } else if (actionId == 'resume' || actionId == 'start_next') {
    unawaited(TimerEngine.resume());
  } else if (actionId == 'skip') {
    unawaited(TimerEngine.skip());
  } else if (actionId == 'extend_5') {
    unawaited(TimerEngine.extend5Min());
  }
}

/// Todo lo relacionado con notificaciones, en un solo lugar.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _runningId = 1; // notificación fija del temporizador
  static const int _endId = 2; // aviso de fin de fase
  static const int _reminderId = 3; // recordatorio diario
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
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId != null) {
          notificationTapBackground(response);
        }
      },
    );
  }

  Future<void> updateDailyReminder(PomodoroSettings s) async {
    try {
      if (!s.dailyReminderEnabled) {
        await _plugin.cancel(id: _reminderId);
        return;
      }

      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        s.dailyReminderHour,
        s.dailyReminderMinute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      const androidDetails = AndroidNotificationDetails(
        'pomodoro_reminder',
        'Recordatorio diario',
        channelDescription: 'Recordatorio diario para empezar a hacer pomodoros',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );

      await _plugin.zonedSchedule(
        id: _reminderId,
        title: 'Pomodoro',
        body: '¿Empezamos un pomodoro?',
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('No se pudo programar el recordatorio diario: $e');
    }
  }

  /// Pide permiso de notificaciones (Android 13+). Devuelve si está concedido.
  Future<bool> ensurePermission() async {
    final android = _android;
    if (android == null) return false;
    if (await android.areNotificationsEnabled() ?? false) return true;
    return await android.requestNotificationsPermission() ?? false;
  }

  Color _phaseColor(PomodoroPhase phase) => switch (phase) {
        PomodoroPhase.focus => const Color(0xFFE53935),
        PomodoroPhase.shortBreak => const Color(0xFF00897B),
        PomodoroPhase.longBreak => const Color(0xFF1E88E5),
      };

  /// En Android 8+ el sonido y la vibración pertenecen al "canal".
  NotificationDetails _endDetails(PomodoroSettings s) {
    final sound = s.soundEnabled;
    final vibration = s.vibrationEnabled;
    final soundName = s.alertSound.rawName;
    final parts = [if (sound) 'sonido ($soundName)', if (vibration) 'vibración'];
    final label = parts.isEmpty ? 'silencioso' : parts.join(' y ');

    return NotificationDetails(
      android: AndroidNotificationDetails(
        'pomodoro_end_s${sound ? 1 : 0}_v${vibration ? 1 : 0}_$soundName',
        'Fin de fase ($label)',
        channelDescription: 'Avisa cuando termina una fase del temporizador',
        importance: Importance.max,
        priority: Priority.high,
        playSound: sound,
        sound: sound ? RawResourceAndroidNotificationSound(soundName) : null,
        enableVibration: vibration,
        vibrationPattern:
            vibration ? Int64List.fromList([0, 500, 250, 500, 250, 500]) : null,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
      ),
    );
  }

  /// Programa el aviso para el momento exacto en que termina la fase.
  Future<bool> scheduleEnd({
    required DateTime endTime,
    required PomodoroPhase endingPhase,
    required PomodoroPhase nextPhase,
    required PomodoroSettings settings,
  }) async {
    final focusEnding = endingPhase == PomodoroPhase.focus;
    final title = focusEnding ? '¡Enfoque terminado!' : 'Descanso terminado';
    final body = focusEnding
        ? 'Es hora de: ${nextPhase.label.toLowerCase()}'
        : 'Listo para el siguiente enfoque';
    final tzDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.UTC,
      endTime.millisecondsSinceEpoch,
    );
    final details = _endDetails(settings);

    try {
      await _plugin.zonedSchedule(
        id: _endId,
        title: title,
        body: body,
        scheduledDate: tzDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint('No se pudo programar la alarma exacta: $e. Intentando inexacta.');
      try {
        await _plugin.zonedSchedule(
          id: _endId,
          title: title,
          body: body,
          scheduledDate: tzDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e2) {
        debugPrint('Tampoco se pudo programar la alarma inexacta: $e2');
      }
      return false;
    }
  }

  /// Notificación fija con cuenta regresiva que dibuja el propio Android.
  Future<void> showRunning({
    required PomodoroPhase phase,
    required DateTime endTime,
    int completedFocus = 0,
    PomodoroSettings? settings,
  }) async {
    try {
      final s = settings ?? const PomodoroSettings();
      final fullStyle = s.notificationStyle == NotificationStyle.full;
      final msLeft = endTime.difference(DateTime.now()).inMilliseconds;

      final cycleNum = (completedFocus % s.cyclesBeforeLongBreak) + 1;
      final title = fullStyle
          ? '${phase.label} · $cycleNum de ${s.cyclesBeforeLongBreak}'
          : phase.label;

      final body = 'En curso · termina a las ${_clock(endTime)}';

      final androidDetails = AndroidNotificationDetails(
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
        color: fullStyle ? _phaseColor(phase) : null,
        colorized: fullStyle,
        styleInformation: fullStyle
            ? BigTextStyleInformation(
                body,
                contentTitle: title,
                summaryText: 'Pomodoro',
              )
            : null,
        actions: fullStyle
            ? const [
                AndroidNotificationAction(
                  'pause',
                  'Pausar',
                  showsUserInterface: false,
                ),
                AndroidNotificationAction(
                  'skip',
                  'Saltar',
                  showsUserInterface: false,
                ),
              ]
            : null,
        timeoutAfter: msLeft > 0 ? msLeft : null,
        visibility: NotificationVisibility.public,
      );

      await _plugin.show(
        id: _runningId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación: $e');
    }
  }

  Future<void> showCompleted({
    required PomodoroPhase finishedPhase,
    required PomodoroSettings settings,
  }) async {
    try {
      final focusFinished = finishedPhase == PomodoroPhase.focus;
      final fullStyle = settings.notificationStyle == NotificationStyle.full;

      final actions = fullStyle
          ? [
              AndroidNotificationAction(
                'start_next',
                focusFinished ? 'Iniciar descanso' : 'Iniciar enfoque',
                showsUserInterface: false,
              ),
              const AndroidNotificationAction(
                'extend_5',
                '+5 min',
                showsUserInterface: false,
              ),
            ]
          : null;

      final sound = settings.soundEnabled;
      final vibration = settings.vibrationEnabled;
      final soundName = settings.alertSound.rawName;
      final parts = [if (sound) 'sonido ($soundName)', if (vibration) 'vibración'];
      final label = parts.isEmpty ? 'silencioso' : parts.join(' y ');

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'pomodoro_end_s${sound ? 1 : 0}_v${vibration ? 1 : 0}_$soundName',
          'Fin de fase ($label)',
          channelDescription: 'Avisa cuando termina una fase del temporizador',
          importance: Importance.max,
          priority: Priority.high,
          playSound: sound,
          sound: sound ? RawResourceAndroidNotificationSound(soundName) : null,
          enableVibration: vibration,
          vibrationPattern: vibration
              ? Int64List.fromList([0, 500, 250, 500, 250, 500])
              : null,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          actions: actions,
        ),
      );

      await _plugin.show(
        id: _endId,
        title: focusFinished ? '¡Enfoque terminado!' : 'Descanso terminado',
        body: focusFinished
            ? '¡Buen trabajo! Tómate un descanso'
            : 'Listo para el siguiente enfoque',
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación de fin: $e');
    }
  }

  Future<void> showPaused({
    required PomodoroPhase phase,
    required Duration remaining,
    PomodoroSettings? settings,
  }) async {
    try {
      final s = settings ?? const PomodoroSettings();
      final fullStyle = s.notificationStyle == NotificationStyle.full;

      await _plugin.show(
        id: _runningId,
        title: '${phase.label} en pausa',
        body: 'Quedan ${_mmss(remaining)}',
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
            showWhen: false,
            color: fullStyle ? _phaseColor(phase) : null,
            colorized: fullStyle,
            actions: fullStyle
                ? const [
                    AndroidNotificationAction(
                      'resume',
                      'Reanudar',
                      showsUserInterface: false,
                    ),
                    AndroidNotificationAction(
                      'skip',
                      'Saltar',
                      showsUserInterface: false,
                    ),
                  ]
                : null,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación: $e');
    }
  }

  Future<void> cancelRunning() async {
    try {
      await _plugin.cancel(id: _runningId);
    } catch (_) {}
  }

  Future<void> cancelEnd() async {
    try {
      await _plugin.cancel(id: _endId);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}