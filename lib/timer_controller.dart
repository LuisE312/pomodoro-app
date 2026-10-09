import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
    this._phaseInitialDuration,
    this._completedFocus,
    this._endTime,
  ) : _isRunning = _endTime != null;

  static const _kPhase = 'timer_phase';
  static const _kRunning = 'timer_running';
  static const _kEnd = 'timer_end_ms';
  static const _kRemaining = 'timer_remaining_ms';
  static const _kCompleted = 'timer_completed';
  static const _kInitial = 'timer_initial_ms';

  PomodoroSettings _settings;
  PomodoroPhase _phase;
  Duration _remaining; // solo vale cuando NO está corriendo
  Duration _phaseInitialDuration; // Duración inicial con la que empezó la fase
  int _completedFocus;
  DateTime? _endTime; // solo vale cuando SÍ está corriendo
  bool _isRunning;
  Timer? _ticker;
  bool _foreground = true;
  final NotificationService _notifications = NotificationService.instance;

  int _todaySessions = 0;

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
    final initialMs = prefs.getInt(_kInitial);

    final initialDuration = initialMs != null
        ? Duration(milliseconds: initialMs)
        : settings.durationOf(phase);

    final controller = TimerController._(
      settings,
      phase,
      remainingMs != null
          ? Duration(milliseconds: remainingMs)
          : initialDuration,
      initialDuration,
      prefs.getInt(_kCompleted) ?? 0,
      running ? DateTime.fromMillisecondsSinceEpoch(endMs) : null,
    );
    WidgetsBinding.instance.addObserver(controller);
    final statsData = await StatsRepository.load();
    controller._todaySessions =
        statsData[StatsRepository.dayKey(DateTime.now())]?.sessions ?? 0;

    await controller._notifications.updateDailyReminder(settings);
    await controller.syncFromClock();
    controller._updateTicker();
    return controller;
  }

  // ---------- Estado visible para la pantalla ----------

  PomodoroSettings get settings => _settings;
  PomodoroPhase get phase => _phase;
  bool get isRunning => _isRunning;
  Duration get total => _phaseInitialDuration;
  int get todaySessions => _todaySessions;

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

  Future<void> _updateWakelock() async {
    try {
      final shouldKeepOn =
          _isRunning && _settings.keepScreenOn && _phase == PomodoroPhase.focus;
      await WakelockPlus.toggle(enable: shouldKeepOn);
    } catch (_) {}
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
    unawaited(_updateWakelock());
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
    await _notifications.showPaused(
      phase: _phase,
      remaining: _remaining,
      settings: _settings,
    );
    unawaited(_updateWakelock());
  }

  Future<void> reset() async {
    _isRunning = false;
    _endTime = null;
    _phaseInitialDuration = _settings.durationOf(_phase);
    _remaining = _phaseInitialDuration;
    _updateTicker();
    notifyListeners();
    await _persist();
    await _notifications.cancelAll();
    unawaited(_updateWakelock());
  }

  /// Salta a la siguiente fase inmediatamente sin incrementar contador ni registrar estadísticas de enfoque.
  Future<void> skip() async {
    _phase = _phaseAfter(_phase, _completedFocus);
    _phaseInitialDuration = _settings.durationOf(_phase);
    _remaining = _phaseInitialDuration;

    if (_isRunning && _settings.autoStartNext) {
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
    unawaited(_updateWakelock());
  }

  /// Extiende la fase actual en 5 minutos.
  Future<void> extend5Min() async {
    const extension = Duration(minutes: 5);
    _phaseInitialDuration += extension;
    if (_isRunning && _endTime != null) {
      _endTime = _endTime!.add(extension);
    } else {
      _remaining += extension;
    }
    notifyListeners();
    await _persist();
    if (_isRunning) {
      await _scheduleNotifications();
    } else {
      await _notifications.showPaused(
        phase: _phase,
        remaining: _remaining,
        settings: _settings,
      );
    }
  }

  Future<void> applySettings(PomodoroSettings updated) async {
    // Si la fase está intacta (no iniciada ni pausada a medias), adopta la nueva duración.
    final untouched = !_isRunning && _remaining == _phaseInitialDuration;
    _settings = updated;
    if (untouched) {
      _phaseInitialDuration = _settings.durationOf(_phase);
      _remaining = _phaseInitialDuration;
    }
    notifyListeners();
    await updated.save();
    await _persist();
    if (_isRunning) await _scheduleNotifications();
    unawaited(_updateWakelock());
    await _notifications.updateDailyReminder(updated);
  }

  /// Si la fase ya debería haber terminado, calcula en bucle las fases transcurridas.
  Future<void> syncFromClock() async {
    if (!_isRunning || _endTime == null) return;

    final now = DateTime.now();
    var phaseEnd = _endTime!;

    if (!now.isBefore(phaseEnd)) {
      while (!now.isBefore(phaseEnd)) {
        final finishedPhase = _phase;
        if (finishedPhase == PomodoroPhase.focus) {
          _completedFocus++;
          _todaySessions++;
          await StatsRepository.recordSession(
            _phaseInitialDuration.inMinutes,
            tag: _settings.selectedTag,
          );
        }

        _phase = _phaseAfter(finishedPhase, _completedFocus);
        _phaseInitialDuration = _settings.durationOf(_phase);

        if (_settings.autoStartNext) {
          phaseEnd = phaseEnd.add(_phaseInitialDuration);
        } else {
          _isRunning = false;
          _endTime = null;
          _remaining = _phaseInitialDuration;
          await _notifications.cancelRunning();
          await _persist();
          notifyListeners();
          return;
        }
      }

      _endTime = phaseEnd;
      _remaining = phaseEnd.difference(now);
      if (_remaining.isNegative) _remaining = Duration.zero;
      await _scheduleNotifications();
      await _persist();
      notifyListeners();
    }
  }

  // ---------- Internos ----------

  PomodoroPhase _phaseAfter(PomodoroPhase finished, int completedFocus) {
    if (finished != PomodoroPhase.focus) return PomodoroPhase.focus;
    final longBreakTurn = completedFocus > 0 &&
        completedFocus % _settings.cyclesBeforeLongBreak == 0;
    return longBreakTurn ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak;
  }

  Future<void> setSelectedTag(String? tag) async {
    _settings = _settings.copyWith(selectedTag: tag);
    notifyListeners();
    await _settings.save();
  }

  void _completePhase() {
    final finished = _phase;
    if (finished == PomodoroPhase.focus) {
      _completedFocus++;
      _todaySessions++;
      unawaited(
        StatsRepository.recordSession(
          _phaseInitialDuration.inMinutes,
          tag: _settings.selectedTag,
        ),
      );
    }

    if (_settings.vibrationEnabled) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }

    _phase = _phaseAfter(finished, _completedFocus);
    _phaseInitialDuration = _settings.durationOf(_phase);
    _remaining = _phaseInitialDuration;

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
    unawaited(_updateWakelock());
  }

  Future<void> _scheduleNotifications() async {
    final end = _endTime;
    if (!_isRunning || end == null) return;
    final completedAfter =
        _phase == PomodoroPhase.focus ? _completedFocus + 1 : _completedFocus;
    await _notifications.scheduleEnd(
      endTime: end,
      endingPhase: _phase,
      nextPhase: _phaseAfter(_phase, completedAfter),
      settings: _settings,
    );
    await _notifications.showRunning(
      phase: _phase,
      endTime: end,
      completedFocus: _completedFocus,
      settings: _settings,
    );
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
    await prefs.setInt(_kInitial, _phaseInitialDuration.inMilliseconds);
    final end = _endTime;
    if (end != null) {
      await prefs.setInt(_kEnd, end.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_kEnd);
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final phaseIndex = (prefs.getInt(_kPhase) ?? 0)
          .clamp(0, PomodoroPhase.values.length - 1);
      _phase = PomodoroPhase.values[phaseIndex];
      _completedFocus = prefs.getInt(_kCompleted) ?? 0;
      final endMs = prefs.getInt(_kEnd);
      _endTime = endMs != null ? DateTime.fromMillisecondsSinceEpoch(endMs) : null;
      _isRunning = (prefs.getBool(_kRunning) ?? false) && _endTime != null;
      final remainingMs = prefs.getInt(_kRemaining);
      final initialMs = prefs.getInt(_kInitial);
      if (initialMs != null) _phaseInitialDuration = Duration(milliseconds: initialMs);
      if (remainingMs != null) _remaining = Duration(milliseconds: remainingMs);

      await syncFromClock();
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