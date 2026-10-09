import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'pomodoro_phase.dart';
import 'settings.dart';

/// Motor puro de estado del temporizador.
/// Opera directamente con SharedPreferences para sincronizar el estado entre
/// el Isolate principal de la UI y el Isolate en segundo plano de las notificaciones.
class TimerEngine {
  static const _kPhase = 'timer_phase';
  static const _kRunning = 'timer_running';
  static const _kEnd = 'timer_end_ms';
  static const _kRemaining = 'timer_remaining_ms';
  static const _kCompleted = 'timer_completed';
  static const _kInitial = 'timer_initial_ms';

  static PomodoroPhase _phaseAfter(
      PomodoroPhase finished, int completedFocus, PomodoroSettings settings) {
    if (finished != PomodoroPhase.focus) return PomodoroPhase.focus;
    final longBreakTurn = completedFocus > 0 &&
        completedFocus % settings.cyclesBeforeLongBreak == 0;
    return longBreakTurn ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak;
  }

  /// Pausa el temporizador desde cualquier Isolate.
  static Future<void> pause() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final running = prefs.getBool(_kRunning) ?? false;
    if (!running) return;

    final endMs = prefs.getInt(_kEnd);
    final phaseIndex = (prefs.getInt(_kPhase) ?? 0).clamp(0, PomodoroPhase.values.length - 1);
    final phase = PomodoroPhase.values[phaseIndex];

    Duration remaining = Duration.zero;
    if (endMs != null) {
      final end = DateTime.fromMillisecondsSinceEpoch(endMs);
      final left = end.difference(DateTime.now());
      remaining = left.isNegative ? Duration.zero : left;
    }

    await prefs.setBool(_kRunning, false);
    await prefs.setInt(_kRemaining, remaining.inMilliseconds);
    await prefs.remove(_kEnd);

    await NotificationService.instance.cancelEnd();
    await NotificationService.instance.showPaused(phase: phase, remaining: remaining);
  }

  /// Reanuda o inicia el temporizador.
  static Future<void> resume() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final running = prefs.getBool(_kRunning) ?? false;
    if (running) return;

    final settings = await PomodoroSettings.load();
    final phaseIndex = (prefs.getInt(_kPhase) ?? 0).clamp(0, PomodoroPhase.values.length - 1);
    final phase = PomodoroPhase.values[phaseIndex];
    final remainingMs = prefs.getInt(_kRemaining);
    final initialMs = prefs.getInt(_kInitial);

    final initialDuration = initialMs != null
        ? Duration(milliseconds: initialMs)
        : settings.durationOf(phase);

    final remaining = remainingMs != null ? Duration(milliseconds: remainingMs) : initialDuration;
    final endTime = DateTime.now().add(remaining);

    await prefs.setBool(_kRunning, true);
    await prefs.setInt(_kEnd, endTime.millisecondsSinceEpoch);

    final completedFocus = prefs.getInt(_kCompleted) ?? 0;
    final completedAfter = phase == PomodoroPhase.focus ? completedFocus + 1 : completedFocus;

    await NotificationService.instance.scheduleEnd(
      endTime: endTime,
      endingPhase: phase,
      nextPhase: _phaseAfter(phase, completedAfter, settings),
      settings: settings,
    );
    await NotificationService.instance.showRunning(
      phase: phase,
      endTime: endTime,
      completedFocus: completedFocus,
      settings: settings,
    );
  }

  /// Salta a la siguiente fase.
  static Future<void> skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final settings = await PomodoroSettings.load();
    final phaseIndex = (prefs.getInt(_kPhase) ?? 0).clamp(0, PomodoroPhase.values.length - 1);
    final currentPhase = PomodoroPhase.values[phaseIndex];
    final completedFocus = prefs.getInt(_kCompleted) ?? 0;
    final wasRunning = prefs.getBool(_kRunning) ?? false;

    final nextPhase = _phaseAfter(currentPhase, completedFocus, settings);
    final nextDuration = settings.durationOf(nextPhase);

    await prefs.setInt(_kPhase, nextPhase.index);
    await prefs.setInt(_kInitial, nextDuration.inMilliseconds);
    await prefs.setInt(_kRemaining, nextDuration.inMilliseconds);

    if (wasRunning && settings.autoStartNext) {
      final endTime = DateTime.now().add(nextDuration);
      await prefs.setBool(_kRunning, true);
      await prefs.setInt(_kEnd, endTime.millisecondsSinceEpoch);

      final completedAfter = nextPhase == PomodoroPhase.focus ? completedFocus + 1 : completedFocus;
      await NotificationService.instance.scheduleEnd(
        endTime: endTime,
        endingPhase: nextPhase,
        nextPhase: _phaseAfter(nextPhase, completedAfter, settings),
        settings: settings,
      );
      await NotificationService.instance.showRunning(
        phase: nextPhase,
        endTime: endTime,
        completedFocus: completedFocus,
        settings: settings,
      );
    } else {
      await prefs.setBool(_kRunning, false);
      await prefs.remove(_kEnd);
      await NotificationService.instance.cancelAll();
    }
  }

  /// Extiende la fase actual en 5 minutos.
  static Future<void> extend5Min() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final settings = await PomodoroSettings.load();
    final phaseIndex = (prefs.getInt(_kPhase) ?? 0).clamp(0, PomodoroPhase.values.length - 1);
    final phase = PomodoroPhase.values[phaseIndex];
    final running = prefs.getBool(_kRunning) ?? false;
    final endMs = prefs.getInt(_kEnd);
    final remainingMs = prefs.getInt(_kRemaining) ?? settings.durationOf(phase).inMilliseconds;
    final initialMs = prefs.getInt(_kInitial) ?? settings.durationOf(phase).inMilliseconds;

    const extension = Duration(minutes: 5);
    final newInitial = Duration(milliseconds: initialMs) + extension;
    await prefs.setInt(_kInitial, newInitial.inMilliseconds);

    if (running && endMs != null) {
      final currentEnd = DateTime.fromMillisecondsSinceEpoch(endMs);
      final newEnd = currentEnd.add(extension);
      await prefs.setInt(_kEnd, newEnd.millisecondsSinceEpoch);

      final completedFocus = prefs.getInt(_kCompleted) ?? 0;
      final completedAfter = phase == PomodoroPhase.focus ? completedFocus + 1 : completedFocus;

      await NotificationService.instance.scheduleEnd(
        endTime: newEnd,
        endingPhase: phase,
        nextPhase: _phaseAfter(phase, completedAfter, settings),
        settings: settings,
      );
      await NotificationService.instance.showRunning(
        phase: phase,
        endTime: newEnd,
        completedFocus: completedFocus,
        settings: settings,
      );
    } else {
      final newRemaining = Duration(milliseconds: remainingMs) + extension;
      await prefs.setInt(_kRemaining, newRemaining.inMilliseconds);
      await NotificationService.instance.showPaused(phase: phase, remaining: newRemaining);
    }
  }
}