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

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva etiqueta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nombre de la etiqueta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && !_s.tags.contains(name)) {
      final updatedTags = List<String>.from(_s.tags)..add(name);
      _apply(_s.copyWith(tags: updatedTags, selectedTag: name));
    }
  }

  Future<void> _renameTag(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar etiqueta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nuevo nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != oldName) {
      final updatedTags = _s.tags.map((t) => t == oldName ? newName : t).toList();
      final updatedSelected = _s.selectedTag == oldName ? newName : _s.selectedTag;
      _apply(_s.copyWith(tags: updatedTags, selectedTag: updatedSelected));
    }
  }

  Future<void> _deleteTag(String tagName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar etiqueta'),
        content: Text('¿Deseas eliminar la etiqueta "$tagName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final updatedTags = List<String>.from(_s.tags)..remove(tagName);
      final updatedSelected = _s.selectedTag == tagName
          ? (updatedTags.isNotEmpty ? updatedTags.first : null)
          : _s.selectedTag;
      _apply(_s.copyWith(tags: updatedTags, selectedTag: updatedSelected));
    }
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restablecer ajustes'),
        content: const Text(
          '¿Deseas restablecer todos los ajustes a los valores predeterminados?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _apply(const PomodoroSettings());
    }
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
          _SliderTile(
            title: 'Meta diaria de pomodoros',
            icon: Icons.flag_outlined,
            value: _s.dailyGoal,
            min: 1,
            max: 16,
            suffix: 'pomodoros',
            onChanged: (v) => _apply(_s.copyWith(dailyGoal: v)),
          ),
          const _SectionHeader('Apariencia'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Tema'),
            trailing: SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text('Sistema'),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text('Claro'),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text('Oscuro'),
                ),
              ],
              selected: {_s.themeMode},
              onSelectionChanged: (set) =>
                  _apply(_s.copyWith(themeMode: set.first)),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Modo AMOLED'),
            subtitle: const Text('Fondo negro puro para pantallas OLED/AMOLED'),
            value: _s.amoledMode,
            onChanged: (v) => _apply(_s.copyWith(amoledMode: v)),
          ),
          const _SectionHeader('Etiquetas'),
          for (final tag in _s.tags)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(tag),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Renombrar',
                    onPressed: () => _renameTag(tag),
                  ),
                  if (_s.tags.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Eliminar',
                      onPressed: () => _deleteTag(tag),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: _addTag,
              icon: const Icon(Icons.add),
              label: const Text('Nueva etiqueta'),
            ),
          ),
          const _SectionHeader('Automatización'),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('Iniciar siguiente fase automáticamente'),
            subtitle: const Text('Arranca la siguiente fase al terminar el tiempo'),
            value: _s.autoStartNext,
            onChanged: (v) => _apply(_s.copyWith(autoStartNext: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screen_lock_portrait_outlined),
            title: const Text('Mantener pantalla encendida'),
            subtitle: const Text('Evita que la pantalla se apague durante el enfoque'),
            value: _s.keepScreenOn,
            onChanged: (v) => _apply(_s.copyWith(keepScreenOn: v)),
          ),
          const _SectionHeader('Avisos'),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Sonido al terminar'),
            value: _s.soundEnabled,
            onChanged: (v) => _apply(_s.copyWith(soundEnabled: v)),
          ),
          if (_s.soundEnabled)
            ListTile(
              leading: const Icon(Icons.queue_music_outlined),
              title: const Text('Sonido de aviso'),
              trailing: DropdownButton<AlertSound>(
                value: _s.alertSound,
                onChanged: (sound) {
                  if (sound != null) _apply(_s.copyWith(alertSound: sound));
                },
                items: [
                  for (final sound in AlertSound.values)
                    DropdownMenuItem(
                      value: sound,
                      child: Text(sound.label),
                    ),
                ],
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibración al terminar'),
            value: _s.vibrationEnabled,
            onChanged: (v) => _apply(_s.copyWith(vibrationEnabled: v)),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Estilo de notificación'),
            subtitle: Text(_s.notificationStyle.description),
            trailing: SegmentedButton<NotificationStyle>(
              segments: const [
                ButtonSegment(
                  value: NotificationStyle.full,
                  label: Text('Completa'),
                ),
                ButtonSegment(
                  value: NotificationStyle.minimal,
                  label: Text('Mínima'),
                ),
              ],
              selected: {_s.notificationStyle},
              onSelectionChanged: (set) =>
                  _apply(_s.copyWith(notificationStyle: set.first)),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.alarm_outlined),
            title: const Text('Recordatorio diario'),
            subtitle: const Text('Recibe un aviso para empezar a hacer pomodoros'),
            value: _s.dailyReminderEnabled,
            onChanged: (v) => _apply(_s.copyWith(dailyReminderEnabled: v)),
          ),
          if (_s.dailyReminderEnabled)
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Hora del recordatorio'),
              trailing: TextButton(
                onPressed: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: _s.dailyReminderHour,
                      minute: _s.dailyReminderMinute,
                    ),
                  );
                  if (time != null) {
                    _apply(
                      _s.copyWith(
                        dailyReminderHour: time.hour,
                        dailyReminderMinute: time.minute,
                      ),
                    );
                  }
                },
                child: Text(
                  '${_s.dailyReminderHour.toString().padLeft(2, '0')}:${_s.dailyReminderMinute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
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