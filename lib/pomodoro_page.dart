import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pomodoro_phase.dart';
import 'settings.dart';
import 'settings_page.dart';

import 'stats.dart';
import 'stats_page.dart';

/// Pantalla principal con el temporizador.
class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key, required this.initialSettings});

  final PomodoroSettings initialSettings;

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  late PomodoroSettings _settings = widget.initialSettings;
  PomodoroPhase _phase = PomodoroPhase.focus;
  late Duration _remaining = _settings.durationOf(_phase);
  bool _isRunning = false;
  int _completedFocus = 0;
  Timer? _timer;
  DateTime? _endTime;
  final AudioPlayer _player = AudioPlayer();

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ---------- Control del temporizador ----------

  void _start() {
    if (_isRunning) return;
    _endTime = DateTime.now().add(_remaining);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    setState(() => _isRunning = true);
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _isRunning = false);
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _remaining = _settings.durationOf(_phase);
      _isRunning = false;
    });
  }

  void _tick() {
    final left = _endTime!.difference(DateTime.now());
    if (left <= Duration.zero) {
      _completePhase();
    } else {
      setState(() => _remaining = left);
    }
  }

  // ---------- Cambio de fase ----------

  /// Decide qué fase sigue: después del enfoque viene un descanso
  /// (largo cada N ciclos); después de un descanso, otro enfoque.
  PomodoroPhase _nextPhase() {
    if (_phase != PomodoroPhase.focus) return PomodoroPhase.focus;
    final isLongBreakTurn =
        _completedFocus % _settings.cyclesBeforeLongBreak == 0;
    return isLongBreakTurn ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak;
  }

  void _completePhase() {
    _timer?.cancel();
    if (_phase == PomodoroPhase.focus) {
      _completedFocus++;
      // Solo se registran las sesiones de enfoque completadas hasta el final.
      StatsRepository.recordSession(_settings.durationOf(_phase).inMinutes);
    }    final next = _nextPhase();
    setState(() {
      _phase = next;
      _remaining = _settings.durationOf(next);
      _isRunning = false;
    });
    _notifyPhaseEnd();
  }

  /// Avisa al usuario con vibración y sonido, según sus ajustes.
  Future<void> _vibrate() async {
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Avisa al usuario con vibración y sonido, según sus ajustes.
  Future<void> _notifyPhaseEnd() async {
    if (_settings.vibrationEnabled) {
      _vibrate();
    }
    if (_settings.soundEnabled) {
      try {
        await _player.play(AssetSource('sounds/bell.wav'));
      } catch (e) {
        debugPrint('No se pudo reproducir el sonido: $e');
      }
    }
  }

  void _openStats() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatsPage()),
    );
  }

  // ---------- Ajustes ----------

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<PomodoroSettings>(
      MaterialPageRoute(builder: (_) => SettingsPage(settings: _settings)),
    );
    if (updated == null) return;
    await updated.save();
    if (!mounted) return;

    // Si el temporizador está intacto, adoptamos la nueva duración.
    // Si está pausado a medias, no borramos su progreso.
    final untouched = !_isRunning && _remaining == _settings.durationOf(_phase);
    setState(() {
      _settings = updated;
      if (untouched) _remaining = _settings.durationOf(_phase);
    });
  }

  // ---------- Presentación ----------

  String get _timeText {
    final totalSeconds = (_remaining.inMilliseconds / 1000).ceil();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Cuántos ciclos del grupo actual están completados (para los puntos).
  int get _filledDots {
    final n = _settings.cyclesBeforeLongBreak;
    final r = _completedFocus % n;
    if (r == 0 && _completedFocus > 0 && _phase == PomodoroPhase.longBreak) {
      return n;
    }
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final total = _settings.durationOf(_phase).inMilliseconds;
    final progress = (1 - _remaining.inMilliseconds / total).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🍅 Pomodoro'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Estadísticas',
            onPressed: _openStats,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _phase.label,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: _phase.color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _settings.cyclesBeforeLongBreak; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      i < _filledDots ? Icons.circle : Icons.circle_outlined,
                      size: 14,
                      color: PomodoroPhase.focus.color,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 10,
                      color: _phase.color,
                      backgroundColor: _phase.color.withValues(alpha: 0.15),
                    ),
                  ),
                  Text(
                    _timeText,
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _isRunning ? _pause : _start,
                  icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(_isRunning ? 'Pausar' : 'Iniciar'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reiniciar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}