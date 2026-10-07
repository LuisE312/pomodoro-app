import 'dart:async';

import 'package:flutter/material.dart';

void main() => runApp(const PomodoroApp());

/// Raíz de la aplicación: define el tema y la primera pantalla.
class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pomodoro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const PomodoroPage(),
    );
  }
}

/// Las fases del ciclo. Cada una tiene nombre, duración y color.
enum PomodoroPhase {
  focus(label: 'Enfoque', duration: Duration(minutes: 25), color: Colors.red),
  rest(label: 'Descanso', duration: Duration(minutes: 5), color: Colors.green);

  const PomodoroPhase({
    required this.label,
    required this.duration,
    required this.color,
  });

  final String label;
  final Duration duration;
  final Color color;
}

/// Pantalla principal. Es "Stateful" porque su contenido cambia con el tiempo.
class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  PomodoroPhase _phase = PomodoroPhase.focus;
  late Duration _remaining = _phase.duration;
  bool _isRunning = false;
  Timer? _timer;
  DateTime? _endTime;

  @override
  void dispose() {
    // Importante: cancelar el timer al cerrar la pantalla.
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_isRunning) return;
    // Guardamos la hora exacta de fin. Así el tiempo no se desfasa
    // aunque el sistema retrase algún "tick" del timer.
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
      _remaining = _phase.duration;
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

  /// Al terminar una fase, pasamos a la siguiente (foco <-> descanso).
  void _completePhase() {
    _timer?.cancel();
    setState(() {
      _phase = _phase == PomodoroPhase.focus
          ? PomodoroPhase.rest
          : PomodoroPhase.focus;
      _remaining = _phase.duration;
      _isRunning = false;
    });
  }

  /// Convierte la duración restante en texto "mm:ss".
  String get _timeText {
    final totalSeconds = (_remaining.inMilliseconds / 1000).ceil();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        1 - _remaining.inMilliseconds / _phase.duration.inMilliseconds;

    return Scaffold(
      appBar: AppBar(title: const Text('🍅 Pomodoro'), centerTitle: true),
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