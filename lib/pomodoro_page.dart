import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'notification_service.dart';
import 'pomodoro_phase.dart';
import 'timer_controller.dart';

String _timeText(Duration remaining) {
  final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

double _fit(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
}

class PomodoroPage extends StatelessWidget {
  const PomodoroPage({super.key, required this.controller});

  final TimerController controller;

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

  /// Pide confirmación solo si hay progreso que perder.
  Future<void> _onReset(BuildContext context) async {
    HapticFeedback.lightImpact();
    final hasProgress = controller.remaining < controller.total;
    if (hasProgress) {
      final ok = await _confirm(
        context,
        title: 'Reiniciar fase',
        body: 'Se perderá el progreso de esta fase.',
        action: 'Reiniciar',
      );
      if (ok != true) return;
    }
    await controller.reset();
  }

  Future<void> _onSkip(BuildContext context) async {
    HapticFeedback.lightImpact();
    final losesSession = controller.phase == PomodoroPhase.focus &&
        controller.remaining < controller.total;
    if (losesSession) {
      final ok = await _confirm(
        context,
        title: 'Saltar enfoque',
        body: 'Esta sesión no se registrará en tus estadísticas.',
        action: 'Saltar',
      );
      if (ok != true) return;
    }
    await controller.skip();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final phase = controller.phase;
        final color = phase.colorIn(scheme);

        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final landscape = c.maxWidth > c.maxHeight;
                final ringSize = landscape
                    ? _fit(c.maxHeight - 48, 180, 340)
                    : _fit(math.min(c.maxWidth - 64, c.maxHeight * 0.42), 200, 340);
                final barWidth = landscape ? 280.0 : _fit(c.maxWidth - 48, 200, 320);

                final header = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PhaseChip(phase: phase, color: color),
                    const SizedBox(height: 16),
                    _DailyGoalBar(
                      done: controller.todaySessions,
                      goal: controller.settings.dailyGoal,
                      color: color,
                      width: barWidth,
                    ),
                    if (controller.settings.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _TagSelector(controller: controller),
                    ],
                  ],
                );

                final ring = _TimerRing(
                  controller: controller,
                  phase: phase,
                  color: color,
                  size: ringSize,
                );

                final dots = _CycleDots(
                  total: controller.settings.cyclesBeforeLongBreak,
                  filled: controller.filledDots,
                  color: color,
                );

                final controls = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => _onReset(context),
                      tooltip: 'Reiniciar',
                      style: IconButton.styleFrom(fixedSize: const Size(56, 56)),
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
                      onPressed: () => _onSkip(context),
                      tooltip: 'Saltar fase',
                      style: IconButton.styleFrom(fixedSize: const Size(56, 56)),
                      icon: const Icon(Icons.skip_next, size: 28),
                    ),
                  ],
                );

                final extend = TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    controller.extend5Min();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('+5 min'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                );

                final Widget body = landscape
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ring,
                          const SizedBox(width: 40),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                header,
                                const SizedBox(height: 20),
                                dots,
                                const SizedBox(height: 20),
                                controls,
                                const SizedBox(height: 8),
                                extend,
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          header,
                          const SizedBox(height: 24),
                          ring,
                          const SizedBox(height: 24),
                          dots,
                          const SizedBox(height: 24),
                          controls,
                          const SizedBox(height: 8),
                          extend,
                        ],
                      );

                // Con scroll y alto mínimo: centrado cuando sobra espacio y sin
                // desbordes en pantallas pequeñas u horizontales.
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight - 32),
                    child: Center(child: body),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Meta del día como barra de progreso (antes: texto con emoji).
class _DailyGoalBar extends StatelessWidget {
  const _DailyGoalBar({
    required this.done,
    required this.goal,
    required this.color,
    required this.width,
  });

  final int done;
  final int goal;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reached = goal > 0 && done >= goal;
    final value = goal <= 0 ? 0.0 : (done / goal).clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: width,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    reached ? Icons.check_circle : Icons.flag_outlined,
                    size: 16,
                    color: reached ? color : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    reached ? 'Meta cumplida' : 'Meta de hoy',
                    style: textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Text(
                '$done / $goal',
                style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value),
              duration: const Duration(milliseconds: 400),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un solo chip con la etiqueta actual; al tocarlo se elige en una hoja inferior.
class _TagSelector extends StatelessWidget {
  const _TagSelector({required this.controller});

  final TimerController controller;

  void _pick(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final settings = controller.settings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿En qué vas a enfocarte?',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in settings.tags)
                      ChoiceChip(
                        label: Text(tag),
                        selected: settings.selectedTag == tag,
                        onSelected: (_) {
                          controller.setSelectedTag(tag);
                          Navigator.pop(ctx);
                        },
                      ),
                    ChoiceChip(
                      label: const Text('Sin etiqueta'),
                      selected: settings.selectedTag == null,
                      onSelected: (_) {
                        controller.setSelectedTag(null);
                        Navigator.pop(ctx);
                      },
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

  @override
  Widget build(BuildContext context) {
    final selected = controller.settings.selectedTag;
    return ActionChip(
      avatar: const Icon(Icons.label_outline, size: 18),
      label: Text(selected ?? 'Sin etiqueta'),
      onPressed: () => _pick(context),
    );
  }
}

/// Anillo + tiempo. Es lo único que se repinta 4 veces por segundo: escucha
/// `controller.ticks`, mientras que el resto de la pantalla solo se reconstruye
/// cuando cambia el estado (iniciar, pausar, cambiar de fase...).
class _TimerRing extends StatelessWidget {
  const _TimerRing({
    required this.controller,
    required this.phase,
    required this.color,
    required this.size,
  });

  final TimerController controller;
  final PomodoroPhase phase;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: controller.ticks,
      builder: (context, _) {
        final remaining = controller.remaining;
        final progress =
            (1 - remaining.inMilliseconds / controller.total.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
        final minutesLeft = (remaining.inSeconds / 60).ceil();

        // La etiqueta cambia solo una vez por minuto (y no 4 veces por
        // segundo) para que TalkBack no esté anunciando todo el rato.
        return Semantics(
          label: 'Fase de ${phase.label}, '
              '${controller.isRunning ? 'en curso' : 'en pausa'}, '
              'quedan $minutesLeft min',
          excludeSemantics: true,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: const Duration(milliseconds: 400),
                  builder: (context, animated, _) => CustomPaint(
                    size: Size.square(size),
                    painter: _RingPainter(
                      progress: progress,
                      color: animated ?? color,
                      track: scheme.surfaceContainerHighest,
                      hole: scheme.surface,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _timeText(remaining),
                      style: textTheme.displayLarge?.copyWith(
                        fontSize: size * 0.21,
                        fontWeight: FontWeight.w300,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      controller.isRunning
                          ? 'En curso'
                          : (remaining < controller.total ? 'En pausa' : 'Listo'),
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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

/// Dibuja el anillo de progreso con extremos redondeados, un halo suave
/// interior y un "pomo" en el punto donde va el progreso.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.hole,
  });

  final double progress;
  final Color color;
  final Color track;
  final Color hole;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.055;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius - stroke,
      Paint()..color = color.withValues(alpha: 0.06),
    );

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

    if (progress > 0 && progress < 1) {
      final angle = -math.pi / 2 + 2 * math.pi * progress;
      final knob = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(knob, stroke * 0.8, Paint()..color = color);
      canvas.drawCircle(knob, stroke * 0.32, Paint()..color = hole);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.hole != hole;
}
