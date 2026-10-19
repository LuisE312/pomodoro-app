import 'package:material_ui/material_ui.dart';

import 'settings.dart';
import 'stats.dart';

const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String _two(int n) => n.toString().padLeft(2, '0');

String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String _duration(int minutes) => minutes < 60
    ? '$minutes min'
    : (minutes % 60 == 0
        ? '${minutes ~/ 60} h'
        : '${minutes ~/ 60} h ${minutes % 60} min');

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  if (day == DateTime(now.year, now.month, now.day)) return 'Hoy';
  if (day == DateTime(now.year, now.month, now.day - 1)) return 'Ayer';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

class _DayHeader {
  const _DayHeader({
    required this.date,
    required this.sessions,
    required this.minutes,
  });

  final DateTime date;
  final int sessions;
  final int minutes;
}

/// Lista de todas las sesiones, agrupadas por día. Permite editarlas (toque),
/// borrarlas (deslizar, con "Deshacer") y añadir una a mano.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<SessionRecord>? _sessions;
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await StatsRepository.loadSessions();
    final settings = await PomodoroSettings.load();
    sessions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _tags = settings.tags;
    });
  }

  Future<void> _edit(SessionRecord? initial) async {
    final result = await showDialog<SessionRecord>(
      context: context,
      builder: (_) => SessionEditor(tags: _tags, initial: initial),
    );
    if (result == null) return;
    if (initial == null) {
      await StatsRepository.addSession(result);
    } else {
      await StatsRepository.updateSession(initial, result);
    }
    await _load();
  }

  Future<void> _delete(SessionRecord s) async {
    setState(() {
      _sessions?.remove(s);
    });
    await StatsRepository.deleteSession(s);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Sesión eliminada'),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () async {
              await StatsRepository.addSession(s);
              await _load();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      floatingActionButton: sessions == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('Añadir sesión'),
            ),
      body: sessions == null
          ? const Center(child: CircularProgressIndicator())
          : (sessions.isEmpty ? _empty(context) : _list(context, sessions)),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text('Sin sesiones todavía', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Aquí aparecerán tus pomodoros. También puedes añadir uno a mano.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<SessionRecord> sessions) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Totales por día y lista plana (cabecera, sesiones, cabecera, ...).
    final counts = <String, int>{};
    final minutes = <String, int>{};
    for (final s in sessions) {
      final k = StatsRepository.dayKey(s.timestamp);
      counts[k] = (counts[k] ?? 0) + 1;
      minutes[k] = (minutes[k] ?? 0) + s.minutes;
    }
    final items = <Object>[];
    String? lastKey;
    for (final s in sessions) {
      final k = StatsRepository.dayKey(s.timestamp);
      if (k != lastKey) {
        items.add(_DayHeader(date: s.timestamp, sessions: counts[k]!, minutes: minutes[k]!));
        lastKey = k;
      }
      items.add(s);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is _DayHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dayLabel(item.date),
                  style: textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${item.sessions} ${item.sessions == 1 ? 'sesión' : 'sesiones'}'
                  ' · ${_duration(item.minutes)}',
                  style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        final s = item as SessionRecord;
        final details = [
          if (s.tag != null) s.tag!,
          if (s.note != null) s.note!,
        ];
        return Dismissible(
          key: ObjectKey(s),
          direction: DismissDirection.endToStart,
          background: Container(
            color: scheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          ),
          onDismissed: (_) => _delete(s),
          child: ListTile(
            onTap: () => _edit(s),
            leading: Icon(Icons.timer_outlined, color: scheme.onSurfaceVariant),
            title: Text('${_time(s.timestamp)} · ${_duration(s.minutes)}'),
            subtitle: details.isEmpty
                ? null
                : Text(details.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        );
      },
    );
  }
}

/// Diálogo para añadir o editar una sesión (fecha, hora, minutos, etiqueta y nota).
class SessionEditor extends StatefulWidget {
  const SessionEditor({super.key, required this.tags, this.initial});

  final List<String> tags;
  final SessionRecord? initial;

  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  late DateTime _when = widget.initial?.timestamp ?? DateTime.now();
  late final TextEditingController _minutes =
      TextEditingController(text: '${widget.initial?.minutes ?? 25}');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');
  late String? _tag = widget.initial?.tag;
  String? _minutesError;

  @override
  void dispose() {
    _minutes.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (t == null || !mounted) return;
    setState(() => _when = DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
  }

  void _save() {
    final m = int.tryParse(_minutes.text.trim());
    if (m == null || m < 1 || m > 600) {
      setState(() => _minutesError = 'Entre 1 y 600 minutos');
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      SessionRecord(
        timestamp: _when.isAfter(now) ? now : _when,
        minutes: m,
        tag: _tag,
        note: _note.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Incluye la etiqueta de la sesión aunque ya no exista en los ajustes.
    final tags = [
      ...widget.tags,
      if (_tag != null && !widget.tags.contains(_tag)) _tag!,
    ];

    return AlertDialog(
      title: Text(widget.initial == null ? 'Añadir sesión' : 'Editar sesión'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('${_when.day} ${_months[_when.month - 1]} ${_when.year}'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text(_time(_when)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Minutos',
                border: const OutlineInputBorder(),
                errorText: _minutesError,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tags)
                  ChoiceChip(
                    label: Text(t),
                    selected: _tag == t,
                    onSelected: (_) => setState(() => _tag = t),
                  ),
                ChoiceChip(
                  label: const Text('Sin etiqueta'),
                  selected: _tag == null,
                  onSelected: (_) => setState(() => _tag = null),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nota',
                hintText: '¿En qué trabajaste?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

/// Diálogo pequeño para escribir solo la nota de una sesión recién terminada.
/// Devuelve el texto (vacío si se quiere quitar) o null si se cancela.
class NoteDialog extends StatefulWidget {
  const NoteDialog({super.key, this.initial});

  final String? initial;

  @override
  State<NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nota de la sesión'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: '¿En qué trabajaste?'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
