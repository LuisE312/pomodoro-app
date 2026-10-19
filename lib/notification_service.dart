import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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

/// Fin de una fase ya calculado: cuándo termina y qué fase viene después.
class PhaseEnd {
  const PhaseEnd({
    required this.endTime,
    required this.endingPhase,
    required this.nextPhase,
  });

  final DateTime endTime;
  final PomodoroPhase endingPhase;
  final PomodoroPhase nextPhase;
}

/// Todo lo relacionado con notificaciones, en un solo lugar.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _runningId = 1; // notificación fija del temporizador
  static const int _endId = 2; // aviso de fin de fase
  static const int _reminderId = 3; // recordatorio diario
  static const int _chainBaseId = 100; // avisos de fases encadenadas: 101..
  static const String _runningChannelId = 'pomodoro_running';

  /// Cuántos fines de fase se programan por adelantado con "inicio automático".
  static const int chainLength = 8;

  /// Lo registra el [TimerController] mientras la app está viva. Si existe, las
  /// acciones de las notificaciones van a él y no al motor sin interfaz.
  Future<void> Function(String actionId)? actionHandler;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    tzdata.initializeTimeZones();
    await _configureLocalTimezone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_timer'),
      ),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (response) {
        final actionId = response.actionId;
        if (actionId == null) return;
        final handler = actionHandler;
        if (handler != null) {
          unawaited(handler(actionId));
        } else {
          notificationTapBackground(response);
        }
      },
    );
  }

  /// Sin esto `tz.local` es UTC y el recordatorio diario sonaría a la hora
  /// equivocada. Acepta tanto la API antigua (String) como la nueva (objeto
  /// con `identifier`) de flutter_timezone.
  Future<void> _configureLocalTimezone() async {
    try {
      final dynamic info = await FlutterTimezone.getLocalTimezone();
      final String name = info is String ? info : info.identifier as String;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      debugPrint('No se pudo detectar la zona horaria, se usa UTC: $e');
    }
  }

  /// Si la app se abrió tocando un botón de una notificación (por ejemplo
  /// "Iniciar descanso") devuelve el id de esa acción.
  Future<String?> launchActionId() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details?.notificationResponse?.actionId;
      }
    } catch (_) {}
    return null;
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
  NotificationDetails _endDetails(
    PomodoroSettings s, {
    required bool focusEnding,
  }) {
    final sound = s.soundEnabled;
    final vibration = s.vibrationEnabled;
    final soundName = s.alertSound.rawName;
    final parts = [if (sound) 'sonido ($soundName)', if (vibration) 'vibración'];
    final label = parts.isEmpty ? 'silencioso' : parts.join(' y ');

    // Con inicio automático la siguiente fase ya arranca sola: sin botón.
    final showAction =
        s.notificationStyle == NotificationStyle.full && !s.autoStartNext;

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
        // showsUserInterface: true abre la app, que es la que avanza de fase
        // y registra la sesión; así el botón funciona aunque la app estuviera
        // cerrada.
        actions: showAction
            ? [
                AndroidNotificationAction(
                  'start_next',
                  focusEnding ? 'Iniciar descanso' : 'Iniciar enfoque',
                  showsUserInterface: true,
                ),
              ]
            : null,
      ),
    );
  }

  /// Programa el aviso para el momento exacto en que termina la fase.
  Future<bool> scheduleEnd({
    required DateTime endTime,
    required PomodoroPhase endingPhase,
    required PomodoroPhase nextPhase,
    required PomodoroSettings settings,
  }) {
    return _scheduleEndAt(
      id: _endId,
      end: PhaseEnd(
        endTime: endTime,
        endingPhase: endingPhase,
        nextPhase: nextPhase,
      ),
      settings: settings,
    );
  }

  /// Programa varios fines de fase seguidos. Con "inicio automático" las fases
  /// siguientes arrancan solas aunque la app esté cerrada, y así suena un aviso
  /// al final de cada una (no solo de la primera).
  Future<void> scheduleEndChain({
    required List<PhaseEnd> ends,
    required PomodoroSettings settings,
  }) async {
    for (var i = 0; i < ends.length; i++) {
      await _scheduleEndAt(
        id: i == 0 ? _endId : _chainBaseId + i,
        end: ends[i],
        settings: settings,
      );
    }
  }

  Future<bool> _scheduleEndAt({
    required int id,
    required PhaseEnd end,
    required PomodoroSettings settings,
  }) async {
    final focusEnding = end.endingPhase == PomodoroPhase.focus;
    final title = focusEnding ? '¡Enfoque terminado!' : 'Descanso terminado';
    final body = focusEnding
        ? 'Es hora de: ${end.nextPhase.label.toLowerCase()}'
        : 'Listo para el siguiente enfoque';
    final tzDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.UTC,
      end.endTime.millisecondsSinceEpoch,
    );
    final details = _endDetails(settings, focusEnding: focusEnding);

    try {
      await _plugin.zonedSchedule(
        id: id,
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
          id: id,
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

  /// Cancela solo los avisos encadenados (fases 2, 3, ... por adelantado).
  Future<void> cancelChain() async {
    try {
      for (var i = 1; i < chainLength; i++) {
        await _plugin.cancel(id: _chainBaseId + i);
      }
    } catch (_) {}
  }

  /// Cancela el aviso de fin de fase y los encadenados.
  Future<void> cancelEnd() async {
    try {
      await _plugin.cancel(id: _endId);
    } catch (_) {}
    await cancelChain();
  }

  /// Cancela lo del temporizador. A propósito NO usa `cancelAll()` del plugin:
  /// eso también borraba el recordatorio diario cada vez que se reiniciaba o
  /// saltaba una fase.
  Future<void> cancelAll() async {
    await cancelRunning();
    await cancelEnd();
  }
}
