import 'package:material_ui/material_ui.dart';

import 'settings.dart';
import 'timer_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final TimerController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late PomodoroSettings _s = widget.controller.settings;

  void _apply(PomodoroSettings updated) {
    setState(() => _s = updated);
    widget.controller.applySettings(updated);
  }

  void _resetDefaults() {
    _apply(const PomodoroSettings());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Restablecer valores por defecto',
            onPressed: _resetDefaults,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('Duraciones'),
          _SliderTile(
            title: 'Enfoque',
            icon: Icons.center_focus_strong_outlined,
            value: _s.focusMinutes,
            min: 1,
            max: 60,
            suffix: 'min',
            onChanged: (v) => _apply(_s.copyWith(focusMinutes: v)),
          ),
          _SliderTile(
            title: 'Descanso corto',
            icon: Icons.coffee_outlined,
            value: _s.shortBreakMinutes,
            min: 1,
            max: 30,
            suffix: 'min',
            onChanged: (v) => _apply(_s.copyWith(shortBreakMinutes: v)),
          ),
          _SliderTile(
            title: 'Descanso largo',
            icon: Icons.self_improvement,
            value: _s.longBreakMinutes,
            min: 1,
            max: 60,
            suffix: 'min',
            onChanged: (v) => _apply(_s.copyWith(longBreakMinutes: v)),
          ),
          _SliderTile(
            title: 'Ciclos antes del descanso largo',
            icon: Icons.repeat,
            value: _s.cyclesBeforeLongBreak,
            min: 2,
            max: 8,
            suffix: 'ciclos',
            onChanged: (v) => _apply(_s.copyWith(cyclesBeforeLongBreak: v)),
          ),
          const _SectionHeader('Automatización'),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('Iniciar siguiente fase automáticamente'),
            subtitle: const Text('Arranca la siguiente fase al terminar el tiempo'),
            value: _s.autoStartNext,
            onChanged: (v) => _apply(_s.copyWith(autoStartNext: v)),
          ),
          const _SectionHeader('Avisos'),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Sonido al terminar'),
            value: _s.soundEnabled,
            onChanged: (v) => _apply(_s.copyWith(soundEnabled: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibración al terminar'),
            value: _s.vibrationEnabled,
            onChanged: (v) => _apply(_s.copyWith(vibrationEnabled: v)),
          ),
          const _SectionHeader('Ayuda'),
          ListTile(
            leading: Icon(
              Icons.battery_saver_outlined,
              color: scheme.onSurfaceVariant,
            ),
            title: const Text('¿No suena con la app cerrada?'),
            subtitle: const Text(
              'En Ajustes de Android > Apps > Pomodoro > Batería, elige '
                  '«Sin restricciones». Algunos teléfonos también tienen '
                  '«Inicio automático».',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Deslizador que solo guarda al soltar, para no escribir en cada pixel.
class _SliderTile extends StatefulWidget {
  const _SliderTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  late double _v = widget.value.toDouble();

  @override
  void didUpdateWidget(covariant _SliderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _v = widget.value.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(child: Text(widget.title)),
              Text(
                '${_v.round()} ${widget.suffix}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          Slider(
            value: _v,
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.max - widget.min,
            label: '${_v.round()}',
            onChanged: (v) => setState(() => _v = v),
            onChangeEnd: (v) => widget.onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}