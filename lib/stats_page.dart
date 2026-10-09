import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'settings.dart';
import 'stats.dart';
import 'achievements.dart';

enum StatsPeriod { week, month }

/// Pantalla de estadísticas avanzadas: resumen, mejor racha, día pico y horario productivo.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsPeriod _period = StatsPeriod.week;

  late Future<({
    Map<String, DayStats> stats,
    List<SessionRecord> sessions,
    PomodoroSettings settings,
  })> _future = _loadData();

  static Future<({
    Map<String, DayStats> stats,
    List<SessionRecord> sessions,
    PomodoroSettings settings,
  })> _loadData() async {
    final stats = await StatsRepository.load();
    final sessions = await StatsRepository.loadSessions();
    final settings = await PomodoroSettings.load();
    return (stats: stats, sessions: sessions, settings: settings);
  }

  static const _weekdayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  String _formatMinutes(int m) {
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }

  Future<void> _export(bool isJson) async {
    try {
      final content = isJson
          ? await StatsRepository.exportJson()
          : await StatsRepository.exportCsv();
      final ext = isJson ? 'json' : 'csv';
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/pomodoro_history_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await file.writeAsString(content);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Historial de Pomodoro ($ext)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar: $e')),
      );
    }
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'csv'],
      );
      if (result != null && result.isNotEmpty && result.single.path != null) {
        final file = File(result.single.path!);
        final content = await file.readAsString();
        if (result.single.extension == 'json') {
          await StatsRepository.importJson(content);
        } else {
          await StatsRepository.importCsv(content);
        }
        if (!mounted) return;
        setState(() => _future = _loadData());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Historial importado correctamente')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al importar: $e')),
      );
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar estadísticas'),
        content: const Text(
          'Se eliminarán todos tus registros de sesiones. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await StatsRepository.clear();
    if (!mounted) return;
    setState(() => _future = _loadData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        actions: [
          FutureBuilder<({
            Map<String, DayStats> stats,
            List<SessionRecord> sessions,
            PomodoroSettings settings,
          })>(
            future: _future,
            builder: (context, snapshot) {
              final sessions = snapshot.data?.sessions ?? [];
              final stats = snapshot.data?.stats ?? {};
              return IconButton(
                icon: const Icon(Icons.emoji_events_outlined),
                tooltip: 'Logros',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AchievementsPage(
                        sessions: sessions,
                        stats: stats,
                      ),
                    ),
                  );
                },
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Opciones',
            onSelected: (value) async {
              if (value == 'export_json') {
                await _export(true);
              } else if (value == 'export_csv') {
                await _export(false);
              } else if (value == 'import') {
                await _import();
              } else if (value == 'clear') {
                await _confirmClear();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export_json',
                child: Text('Exportar como JSON'),
              ),
              const PopupMenuItem(
                value: 'export_csv',
                child: Text('Exportar como CSV'),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Text('Importar historial'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Borrar estadísticas'),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<({
        Map<String, DayStats> stats,
        List<SessionRecord> sessions,
        PomodoroSettings settings,
      })>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildContent(
            context,
            snapshot.data!.stats,
            snapshot.data!.sessions,
            snapshot.data!.settings,
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, DayStats> data,
    List<SessionRecord> sessionsList,
    PomodoroSettings settings,
  ) {
    final now = DateTime.now();
    final numDays = _period == StatsPeriod.week ? 7 : 30;

    final days = List.generate(
      numDays,
      (i) => DateTime(now.year, now.month, now.day - (numDays - 1 - i)),
    );

    final stats = [
      for (final d in days) data[StatsRepository.dayKey(d)] ?? const DayStats(),
    ];

    final today = stats.last;
    final totalSessions = stats.fold<int>(0, (sum, s) => sum + s.sessions);
    final totalMinutes = stats.fold<int>(0, (sum, s) => sum + s.minutes);
    final maxSessions = max(1, stats.map((s) => s.sessions).reduce(max));

    final currentStreak = StatsRepository.calculateStreak(data);
    final bestStreak = StatsRepository.calculateBestStreak(data);
    final bestDayEntry = StatsRepository.getBestDay(data);
    final bestSlot = StatsRepository.getMostProductiveTimeSlot(sessionsList);

    final periodStartDate = days.first;
    final periodEndDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final Map<String, ({int sessions, int minutes})> tagStats = {};
    for (final s in sessionsList) {
      if (s.timestamp.isAfter(periodStartDate.subtract(const Duration(seconds: 1))) &&
          s.timestamp.isBefore(periodEndDate.add(const Duration(seconds: 1)))) {
        final tagName = s.tag ?? 'Sin etiqueta';
        final current = tagStats[tagName] ?? (sessions: 0, minutes: 0);
        tagStats[tagName] = (
          sessions: current.sessions + 1,
          minutes: current.minutes + s.minutes,
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: SegmentedButton<StatsPeriod>(
            segments: const [
              ButtonSegment(
                value: StatsPeriod.week,
                label: Text('Semana (7d)'),
                icon: Icon(Icons.calendar_view_week),
              ),
              ButtonSegment(
                value: StatsPeriod.month,
                label: Text('Mes (30d)'),
                icon: Icon(Icons.calendar_view_month),
              ),
            ],
            selected: {_period},
            onSelectionChanged: (set) => setState(() => _period = set.first),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Hoy',
                sessions: today.sessions,
                time: _formatMinutes(today.minutes),
                icon: Icons.today,
                subtitle: 'Meta: ${today.sessions}/${settings.dailyGoal} 🎯',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: _period == StatsPeriod.week ? 'Últimos 7 días' : 'Últimos 30 días',
                sessions: totalSessions,
                time: _formatMinutes(totalMinutes),
                icon: Icons.date_range,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Racha actual / mejor',
                              style: Theme.of(context).textTheme.labelMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$currentStreak / $bestStreak días',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        color: Theme.of(context).colorScheme.tertiary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Franja más activa',
                              style: Theme.of(context).textTheme.labelMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              bestSlot,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (bestDayEntry != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.emoji_events_outlined,
                color: Theme.of(context).colorScheme.secondary,
                size: 28,
              ),
              title: const Text('Mejor día histórico'),
              subtitle: Text(
                '${bestDayEntry.key}: ${bestDayEntry.value.sessions} sesiones (${_formatMinutes(bestDayEntry.value.minutes)})',
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          _period == StatsPeriod.week ? 'Sesiones por día (Semana)' : 'Sesiones por día (Mes)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 170,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < days.length; i++)
                _Bar(
                  count: stats[i].sessions,
                  minutes: stats[i].minutes,
                  maxCount: maxSessions,
                  label: _period == StatsPeriod.week
                      ? _weekdayLabels[days[i].weekday - 1]
                      : '${days[i].day}',
                  isToday: i == days.length - 1,
                  formattedMinutes: _formatMinutes(stats[i].minutes),
                  compact: _period == StatsPeriod.month,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Tiempo por etiqueta',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (tagStats.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No hay sesiones registradas con etiquetas en este período.'),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final entry in tagStats.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.label, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                            ],
                          ),
                          Text(
                            '${entry.value.sessions} ${entry.value.sessions == 1 ? 'sesión' : 'sesiones'} (${_formatMinutes(entry.value.minutes)})',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Tarjeta con el número de sesiones y el tiempo total.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.sessions,
    required this.time,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final int sessions;
  final String time;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, size: 18, color: colorScheme.outline),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$sessions',
              style: textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(sessions == 1 ? 'sesión' : 'sesiones'),
            const SizedBox(height: 4),
            Text(time, style: textTheme.bodySmall),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Una barra del gráfico semanal/mensual con información al tocar.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.count,
    required this.minutes,
    required this.maxCount,
    required this.label,
    required this.isToday,
    required this.formattedMinutes,
    this.compact = false,
  });

  final int count;
  final int minutes;
  final int maxCount;
  final String label;
  final bool isToday;
  final String formattedMinutes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tooltipText = '$label: $count ${count == 1 ? 'sesión' : 'sesiones'} ($formattedMinutes)';

    return Tooltip(
      message: tooltipText,
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tooltipText),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!compact) Text('$count'),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: compact ? 6 : 28,
              height: count == 0 ? 4 : 100 * count / maxCount,
              decoration: BoxDecoration(
                color: isToday
                    ? colors.primary
                    : (count == 0 ? colors.surfaceContainerHighest : colors.secondary),
                borderRadius: BorderRadius.circular(compact ? 2 : 6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 9 : 12,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                color: isToday ? colors.primary : colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}