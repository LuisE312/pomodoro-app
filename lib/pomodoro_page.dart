import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'notification_service.dart';
import 'pomodoro_phase.dart';
import 'timer_controller.dart';

class PomodoroPage extends StatelessWidget {
  const PomodoroPage({super.key, required this.controller});

  final TimerController controller;

  static const double _ringSize = 280;

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final phase = controller.phase;
        final color = phase.colorIn(scheme);
        final remaining = controller.remaining;
        final progress =
        (1 - remaining.inMilliseconds / controller.total.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                _PhaseChip(phase: phase, color: color),
                const SizedBox(height: 8),
                Text(
                  'Meta diaria: ${controller.todaySessions} / ${controller.settings.dailyGoal} 🎯',
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (controller.settings.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final tag in controller.settings.tags)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FilterChip(
                              label: Text(tag),
                              selected: controller.settings.selectedTag == tag,
                              onSelected: (selected) {
                                HapticFeedback.selectionClick();
                                controller.setSelectedTag(selected ? tag : null);
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                Semantics(
                  label: 'Fase de ${phase.label}, quedan ${_timeText(remaining)}, ${controller.isRunning ? 'en curso' : 'en pausa'}',
                  child: SizedBox(
                    width: _ringSize,
                    height: _ringSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        TweenAnimationBuilder<Color?>(
                          tween: ColorTween(end: color),
                          duration: const Duration(milliseconds: 400),
                          builder: (context, animated, _) => CustomPaint(
                            size: const Size.square(_ringSize),
                            painter: _RingPainter(
                              progress: progress,
                              color: animated ?? color,
                              track: scheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeText(remaining),
                              style: textTheme.displayLarge?.copyWith(
                                fontWeight: FontWeight.w300,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              controller.isRunning
                                  ? 'En curso'
                                  : (controller.remaining < controller.total
                                      ? 'En pausa'
                                      : 'Listo'),
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _CycleDots(
                  total: controller.settings.cyclesBeforeLongBreak,
                  filled: controller.filledDots,
                  color: color,
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        controller.reset();
                      },
                      tooltip: 'Reiniciar',
                      style: IconButton.styleFrom(
                        fixedSize: const Size(56, 56),
                      ),
                      icon: const Icon(Icons.refresh, size: 28),
                    ),
                    const SizedBox(width: 24),
                    _PlayButton(
                      running: controller.isRunning,
                      color: color,
                      onColor: phase.onColorIn(scheme),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        if (controller.isRunning) {
                          controller.pause();
                        } else {
                          _onStart(context);
                        }
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton.filledTonal(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        controller.skip();
                      },
                      tooltip: 'Saltar fase',
                      style: IconButton.styleFrom(
                        fixedSize: const Size(56, 56),
                      ),
                      icon: const Icon(Icons.skip_next, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    controller.extend5Min();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('+5 min'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Píldora que muestra la fase actual.
class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase, required this.color});

  final PomodoroPhase phase;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(phase.icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            phase.label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Puntos de progreso del grupo de ciclos: el lleno se alarga.
class _CycleDots extends StatelessWidget {
  const _CycleDots({
    required this.total,
    required this.filled,
    required this.color,
  });

  final int total;
  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i < filled ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i < filled ? color : color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

/// Botón grande que pasa de círculo a cuadrado redondeado al iniciar.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.running,
    required this.color,
    required this.onColor,
    required this.onPressed,
  });

  final bool running;
  final Color color;
  final Color onColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: running ? 'Pausar' : 'Iniciar',
      child: Material(
        color: color,
        animationDuration: const Duration(milliseconds: 300),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(running ? 28 : 48),
        ),
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 96,
            height: 96,
            child: Icon(
              running ? Icons.pause : Icons.play_arrow,
              size: 44,
              color: onColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dibuja el anillo de progreso con extremos redondeados.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset(stroke / 2, stroke / 2) &
    Size(size.width - stroke, size.height - stroke);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}