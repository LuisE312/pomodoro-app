import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';
import 'pomodoro_phase.dart';
import 'settings.dart';
import 'stats.dart';

/// Lógica del temporizador, independiente de la pantalla.
class TimerController extends ChangeNotifier with WidgetsBindingObserver {
  TimerController._(
      this._settings,
      this._phase,
      this._remaining,
      this._completedFocus,
      this._endTime,
      ) : _isRunning = _endTime != null;

  static const _kPhase = 'timer_phase';
  static const _kRunning = 'timer_running';
  static const _kEnd = 'timer_end_ms';
  static const _kRemaining = 'timer_remaining_ms';
  static const _kCompleted = 'timer_completed';

  PomodoroSettings _settings;
  PomodoroPhase _phase;
  Duration _remaining; // solo vale cuando NO está corriendo
  int _completedFocus;
  DateTime? _endTime; // solo vale cuando SÍ está corriendo
  bool _isRunning;
  Timer? _ticker;
  bool _foreground = true;
  final NotificationService _notifications = NotificationService.instance;

  /// Recupera el estado guardado (si lo hay) y deja el controlador listo.
  static Future<TimerController> load(PomodoroSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final phaseIndex = (prefs.getInt(_kPhase) ?? 0)
        .clamp(0, PomodoroPhase.values.length - 1)
        .toInt();
    final phase = PomodoroPhase.values[phaseIndex];
    final endMs = prefs.getInt(_kEnd);
    final running = (prefs.getBool(_kRunning) ?? false) && endMs != null;
    final remainingMs = prefs.getInt(_kRemaining);

    final controller = TimerController._(
      settings,
      phase,
      remainingMs != null
          ? Duration(milliseconds: remainingMs)
          : settings.durationOf(phase),
      prefs.getInt(_kCompleted) ?? 0,
      running ? DateTime.fromMillisecondsSinceEpoch(endMs) : null,
    );
    WidgetsBinding.instance.addObserver(controller);
    // Si la fase terminó mientras la app estaba cerrada, la cerramos ahora.
    controller.syncFromClock();
    controller._updateTicker();
    return controller;
  }

  // ---------- Estado visible para la pantalla ----------

  PomodoroSettings get settings => _settings;
  PomodoroPhase get phase => _phase;
  bool get isRunning => _isRunning;
  Duration get total => _settings.durationOf(_phase);

  Duration get remaining {
    final end = _endTime;
    if (_isRunning && end != null) {
      final left = end.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }
    return _remaining;
  }

  /// Cuántos puntos del grupo actual están completos.
  int get filledDots {
    final n = _settings.cyclesBeforeLongBreak;
    final r = _completedFocus % n;
    if (r == 0 && _completedFocus > 0 && _phase == PomodoroPhase.longBreak) {
      return n;
    }
    return r;
  }

  // ---------- Acciones ----------

  Future<void> start() async {
    if (_isRunning) return;
    _endTime = DateTime.now().add(_remaining);
    _isRunning = true;
    _updateTicker();
    notifyListeners();
    await _persist();
    await _scheduleNotifications();
  }

  Future<void> pause() async {
    if (!_isRunning) return;
    _remaining = remaining;
    _isRunning = false;
    _endTime = null;
    _updateTicker();
    notifyListeners();
    await _persist();
    await _notifications.cancelEnd();
    await _notifications.showPaused(phase: _phase, remaining: _remaining);
  }

  Future<void> reset() async {
    _isRunning = false;
    _endTime = null;
    _remaining = _settings.durationOf(_phase);
    _updateTicker();
    notifyListeners();
    await _persist();
    await _notifications.cancelAll();
  }

  /// Salta a la siguiente fase inmediatamente.
  Future<void> skip() async {
    final finished = _phase;
    final wasRunning = _isRunning;

    if (finished == PomodoroPhase.focus) {
      _completedFocus++;
      unawaited(
        StatsRepository.recordSession(_settings.durationOf(finished).inMinutes),
      );
    }

    _phase = _phaseAfter(finished, _completedFocus);
    _remaining = _settings.durationOf(_phase);

    if (wasRunning && _settings.autoStartNext) {
      _endTime = DateTime.now().add(_remaining);
      _isRunning = true;
      await _scheduleNotifications();
    } else {
      _isRunning = false;
      _endTime = null;
      await _notifications.cancelAll();
    }

    _updateTicker();
    notifyListeners();
    await _persist();
  }

  Future<void> applySettings(PomodoroSettings updated) async {
    // Si el temporizador está intacto, adoptamos la nueva duración.
    // Si está pausado a medias, no borramos su progreso.
    final untouched = !_isRunning && _remaining == _settings.durationOf(_phase);
    _settings = updated;
    if (untouched) _remaining = _settings.durationOf(_phase);
    notifyListeners();
    await updated.save();
    await _persist();
    if (_isRunning) await _scheduleNotifications();
  }

  /// Si la fase ya debería haber terminado, la cierra y pasa a la siguiente.
  void syncFromClock() {
    final end = _endTime;
    if (_isRunning && end != null && !DateTime.now().isBefore(end)) {
      _completePhase();
    }
  }

  // ---------- Internos ----------

  PomodoroPhase _phaseAfter(PomodoroPhase finished, int completedFocus) {
    if (finished != PomodoroPhase.focus) return PomodoroPhase.focus;
    final longBreakTurn = completedFocus % _settings.cyclesBeforeLongBreak == 0;
    return longBreakTurn ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak;
  }

  void _completePhase() {
    final finished = _phase;
    if (finished == PomodoroPhase.focus) {
      _completedFocus++;
      unawaited(
        StatsRepository.recordSession(_settings.durationOf(finished).inMinutes),
      );
    }
    unawaited(
      _notifications.showCompleted(
        finishedPhase: finished,
        settings: _settings,
      ),
    );

    _phase = _phaseAfter(finished, _completedFocus);
    _remaining = _settings.durationOf(_phase);

    if (_settings.autoStartNext) {
      _endTime = DateTime.now().add(_remaining);
      _isRunning = true;
      unawaited(_scheduleNotifications());
    } else {
      _isRunning = false;
      _endTime = null;
      unawaited(_notifications.cancelRunning());
    }

    _updateTicker();
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _scheduleNotifications() async {
    final end = _endTime;
    if (!_isRunning || end == null) return;
    final completedAfter =
    _phase == PomodoroPhase.focus ? _completedFocus + 1 : _completedFocus;
    await _notifications.cancelEnd();
    await _notifications.scheduleEnd(
      endTime: end,
      endingPhase: _phase,
      nextPhase: _phaseAfter(_phase, completedAfter),
      settings: _settings,
    );
    await _notifications.showRunning(phase: _phase, endTime: end);
  }

  /// Refresca la pantalla 4 veces por segundo, solo si la app está a la vista.
  void _updateTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (_isRunning && _foreground) {
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final end = _endTime;
        if (end != null && !DateTime.now().isBefore(end)) {
          _completePhase();
        } else {
          notifyListeners();
        }
      });
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPhase, _phase.index);
    await prefs.setBool(_kRunning, _isRunning);
    await prefs.setInt(_kCompleted, _completedFocus);
    await prefs.setInt(_kRemaining, _remaining.inMilliseconds);
    final end = _endTime;
    if (end != null) {
      await prefs.setInt(_kEnd, end.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_kEnd);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      syncFromClock();
      _updateTicker();
      notifyListeners();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      _updateTicker();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }
}