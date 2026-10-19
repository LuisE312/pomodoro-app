import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'notification_service.dart';
import 'pomodoro_phase.dart';
import 'settings.dart';
import 'achievements.dart';
import 'stats.dart';
import 'timer_engine.dart';

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
  DateTime _today = DateTime.now(); // día al que pertenece _todaySessions
  bool _disposed = false;
  final _TickNotifier _ticks = _TickNotifier();
  late final ValueNotifier<PomodoroSettings> _settingsNotifier =
      ValueNotifier<PomodoroSettings>(_settings);

  static const String _kSeenAchievements = 'achievements_seen';
  final ValueNotifier<SessionEvent?> _sessionEvents =
      ValueNotifier<SessionEvent?>(null);
  Set<String> _seenAchievements = {};

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

    NotificationService.instance.actionHandler =
        controller.handleNotificationAction;

    await controller._loadSeenAchievements();
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

  /// Sesiones de enfoque de hoy. Si cambió el día y aún no se recontó, 0.
  int get todaySessions => _isToday(_today) ? _todaySessions : 0;

  /// Cambia solo cuando cambian los ajustes (tema, etiquetas, duraciones...).
  /// La `MaterialApp` escucha esto y no el reloj.
  ValueListenable<PomodoroSettings> get settingsListenable => _settingsNotifier;

  /// Late 4 veces por segundo mientras corre el reloj. Solo lo escucha el
  /// anillo del temporizador, para no reconstruir toda la pantalla.
  Listenable get ticks => _ticks;

  /// Se actualiza cada vez que se registra una sesión de enfoque (con los
  /// logros que desbloqueó, si alguno). La interfaz lo usa para avisar.
  ValueListenable<SessionEvent?> get sessionEvents => _sessionEvents;

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
    _setSettings(updated);
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
    _rollDayIfNeeded();
    if (!_isRunning || _endTime == null) return;

    final now = DateTime.now();
    var phaseEnd = _endTime!;

    if (!now.isBefore(phaseEnd)) {
      while (!now.isBefore(phaseEnd)) {
        final finishedPhase = _phase;
        if (finishedPhase == PomodoroPhase.focus) {
          _completedFocus++;
          // La sesión terminó en `phaseEnd`, no ahora: así cae en el día y la
          // franja horaria correctos aunque la app estuviera cerrada.
          if (_isSameDay(phaseEnd, now)) _todaySessions++;
          await StatsRepository.recordSession(
            _phaseInitialDuration.inMinutes,
            tag: _settings.selectedTag,
            at: phaseEnd,
          );
          await _emitSessionEvent(
            phaseEnd,
            _phaseInitialDuration.inMinutes,
            _settings.selectedTag,
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

  PomodoroPhase _phaseAfter(PomodoroPhase finished, int completedFocus) =>
      TimerEngine.phaseAfter(finished, completedFocus, _settings);

  void _setSettings(PomodoroSettings updated) {
    _settings = updated;
    _settingsNotifier.value = updated;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) => _isSameDay(d, DateTime.now());

  /// Si cambió el día, el contador de "hoy" vuelve a cero y se recuenta.
  void _rollDayIfNeeded() {
    if (_isToday(_today)) return;
    _today = DateTime.now();
    _todaySessions = 0;
    notifyListeners();
    unawaited(_reloadToday());
  }

  /// Relee de las estadísticas cuántas sesiones van hoy.
  Future<void> _reloadToday() async {
    final data = await StatsRepository.load();
    if (_disposed) return;
    _today = DateTime.now();
    _todaySessions = data[StatsRepository.dayKey(_today)]?.sessions ?? 0;
    notifyListeners();
  }

  /// Punto único de entrada para los botones de las notificaciones cuando la
  /// app está viva (o se acaba de abrir por uno de ellos).
  Future<void> handleNotificationAction(String actionId) async {
    // En segundo plano el reloj de la UI está parado: ponemos el estado al día.
    await syncFromClock();
    if (actionId == 'pause') {
      await pause();
    } else if (actionId == 'resume' || actionId == 'start_next') {
      await start(); // no hace nada si ya está corriendo
    } else if (actionId == 'skip') {
      await skip();
    } else if (actionId == 'extend_5') {
      await extend5Min();
    }
  }

  Future<void> setSelectedTag(String? tag) async {
    _setSettings(_settings.copyWith(selectedTag: tag));
    notifyListeners();
    await _settings.save();
  }

  void _completePhase() {
    final finished = _phase;
    if (finished == PomodoroPhase.focus) {
      _completedFocus++;
      _todaySessions++;
      final minutes = _phaseInitialDuration.inMinutes;
      final tag = _settings.selectedTag;
      final at = DateTime.now();
      unawaited(
        StatsRepository.recordSession(minutes, tag: tag, at: at)
            .then((_) => _emitSessionEvent(at, minutes, tag)),
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

  /// Logros desbloqueados con el historial actual.
  Future<List<Achievement>> _currentUnlocked() async {
    final sessions = await StatsRepository.loadSessions();
    final stats = await StatsRepository.load();
    return Achievement.evaluate(sessions, stats).where((a) => a.unlocked).toList();
  }

  /// Carga qué logros ya se anunciaron. La primera vez (por ejemplo, al
  /// actualizar la app) los que ya tienes se marcan como vistos para no
  /// anunciarlos todos de golpe.
  Future<void> _loadSeenAchievements() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kSeenAchievements);
      if (saved != null) {
        _seenAchievements = saved.toSet();
        return;
      }
      final unlocked = await _currentUnlocked();
      _seenAchievements = unlocked.map((a) => a.id).toSet();
      await prefs.setStringList(_kSeenAchievements, _seenAchievements.toList());
    } catch (e) {
      debugPrint('No se pudieron leer los logros vistos: $e');
    }
  }

  /// Avisa a la interfaz de que se registró una sesión y de qué logros
  /// nuevos desbloqueó.
  Future<void> _emitSessionEvent(DateTime at, int minutes, String? tag) async {
    try {
      final fresh = (await _currentUnlocked())
          .where((a) => !_seenAchievements.contains(a.id))
          .toList();
      if (fresh.isNotEmpty) {
        _seenAchievements.addAll(fresh.map((a) => a.id));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_kSeenAchievements, _seenAchievements.toList());
      }
      if (_disposed) return;
      _sessionEvents.value = SessionEvent(
        timestamp: at,
        minutes: minutes,
        tag: tag,
        unlocked: fresh,
      );
    } catch (e) {
      debugPrint('No se pudo emitir el evento de sesión: $e');
    }
  }

  Future<void> _scheduleNotifications() async {
    final end = _endTime;
    if (!_isRunning || end == null) return;

    // Con inicio automático las fases siguientes arrancan solas aunque la app
    // esté cerrada: se programa un aviso al final de cada una por adelantado.
    // Sin inicio automático solo hay un aviso (y se limpian los sobrantes).
    final steps = _settings.autoStartNext ? NotificationService.chainLength : 1;
    final ends = <PhaseEnd>[];
    var phase = _phase;
    var completed = _completedFocus;
    var at = end;
    for (var i = 0; i < steps; i++) {
      final completedAfter =
          phase == PomodoroPhase.focus ? completed + 1 : completed;
      final next = _phaseAfter(phase, completedAfter);
      ends.add(PhaseEnd(endTime: at, endingPhase: phase, nextPhase: next));
      completed = completedAfter;
      phase = next;
      at = at.add(_settings.durationOf(next));
    }
    if (steps == 1) await _notifications.cancelChain();
    await _notifications.scheduleEndChain(ends: ends, settings: _settings);
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
        _rollDayIfNeeded();
        final end = _endTime;
        if (end != null && !DateTime.now().isBefore(end)) {
          _completePhase();
        } else {
          _ticks.tick(); // solo repinta el anillo, no toda la app
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

      _rollDayIfNeeded();
      await syncFromClock();
      await _reloadToday();
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
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    if (NotificationService.instance.actionHandler == handleNotificationAction) {
      NotificationService.instance.actionHandler = null;
    }
    _ticker?.cancel();
    _ticks.dispose();
    _settingsNotifier.dispose();
    _sessionEvents.dispose();
    super.dispose();
  }
}

/// `ChangeNotifier` cuyo único propósito es avisar de cada tick del reloj.
/// (`notifyListeners` es protegido, por eso hace falta la subclase.)
class _TickNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Una sesión de enfoque acaba de registrarse. [unlocked] son los logros que
/// esa sesión desbloqueó por primera vez (normalmente, ninguno).
class SessionEvent {
  const SessionEvent({
    required this.timestamp,
    required this.minutes,
    this.tag,
    this.unlocked = const [],
  });

  final DateTime timestamp;
  final int minutes;
  final String? tag;
  final List<Achievement> unlocked;
}
