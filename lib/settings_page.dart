import 'package:flutter/material.dart';

import 'settings.dart';

/// Pantalla de ajustes. Devuelve los nuevos ajustes al pulsar "Guardar".
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final PomodoroSettings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late PomodoroSettings _s = widget.settings;

  Widget _slider({
    required String title,
    required int value,
    required int min,
    required int max,
    required String suffix,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text('$title: $value $suffix'),
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          _slider(
            title: 'Enfoque',
            value: _s.focusMinutes,
            min: 1,
            max: 60,
            suffix: 'min',
            onChanged: (v) => setState(() => _s = _s.copyWith(focusMinutes: v)),
          ),
          _slider(
            title: 'Descanso corto',
            value: _s.shortBreakMinutes,
            min: 1,
            max: 30,
            suffix: 'min',
            onChanged: (v) =>
                setState(() => _s = _s.copyWith(shortBreakMinutes: v)),
          ),
          _slider(
            title: 'Descanso largo',
            value: _s.longBreakMinutes,
            min: 1,
            max: 60,
            suffix: 'min',
            onChanged: (v) =>
                setState(() => _s = _s.copyWith(longBreakMinutes: v)),
          ),
          _slider(
            title: 'Ciclos antes del descanso largo',
            value: _s.cyclesBeforeLongBreak,
            min: 2,
            max: 8,
            suffix: 'ciclos',
            onChanged: (v) =>
                setState(() => _s = _s.copyWith(cyclesBeforeLongBreak: v)),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Sonido al terminar'),
            value: _s.soundEnabled,
            onChanged: (v) => setState(() => _s = _s.copyWith(soundEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Vibración al terminar'),
            value: _s.vibrationEnabled,
            onChanged: (v) =>
                setState(() => _s = _s.copyWith(vibrationEnabled: v)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_s),
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}