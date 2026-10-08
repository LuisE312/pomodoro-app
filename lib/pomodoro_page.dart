import 'package:flutter/material.dart';

import 'notification_service.dart';
import 'pomodoro_phase.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'timer_controller.dart';

class PomodoroPage extends StatelessWidget {
  const PomodoroPage({super.key, required this.controller});

  final TimerController controller;

  String _timeText(Duration remaining) {
    final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _onStart(BuildContext context) async {
    final granted = await NotificationService.instance.ensurePermission();
    await controller.start();
    if (!granted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin permiso de notificaciones no podremos avisarte con la app '
                'cerrada. Actívalo en Ajustes de Android > Apps > Pomodoro.',
          ),
        ),
      );
    }
  }

  Future<void> _openSettings(BuildContext context) async {
    final updated = await Navigator.of(context).push<PomodoroSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(settings: controller.settings),
      ),
    );
    if (updated != null) await controller.applySettings(updated);
  }

  void _openStats(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.phase;
        final remaining = controller.remaining;
        final total = controller.total.inMilliseconds;
        final progress =
        (1 - remaining.inMilliseconds / total).clamp(0.0, 1.0);

        return Scaffold(
          appBar: AppBar(
            title: const Text('🍅 Pomodoro'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.bar_chart),
                tooltip: 'Estadísticas',
                onPressed: () => _openStats(context),
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Ajustes',
                onPressed: () => _openSettings(context),
              ),
            ],
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  phase.label,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: phase.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0;
                    i < controller.settings.cyclesBeforeLongBreak;
                    i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          i < controller.filledDots
                              ? Icons.circle
                              : Icons.circle_outlined,
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
                          color: phase.color,
                          backgroundColor: phase.color.withValues(alpha: 0.15),
                        ),
                      ),
                      Text(
                        _timeText(remaining),
                        style:
                        Theme.of(context).textTheme.displayLarge?.copyWith(
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
                      onPressed: controller.isRunning
                          ? controller.pause
                          : () => _onStart(context),
                      icon: Icon(
                        controller.isRunning ? Icons.pause : Icons.play_arrow,
                      ),
                      label: Text(controller.isRunning ? 'Pausar' : 'Iniciar'),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: controller.reset,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reiniciar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}