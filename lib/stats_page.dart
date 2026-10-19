import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'settings.dart';
import 'stats.dart';
import 'achievements.dart';
import 'history_page.dart';

enum StatsPeriod { week, month }

/// Pantalla de estadísticas avanzadas: resumen, mejor racha, día pico y horario productivo.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsPeriod _period = StatsPeriod.week;
  int _offset = 0; // 0 = período actual; 1 = el anterior, etc.

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

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Historial de Pomodoro ($ext)',
        ),
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
      if (result.isNotEmpty && result.single.path != null) {
        final file = File(result.single.path!);
        final content = await file.readAsString();
        if (!mounted) return;

        final mode = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Importar historial'),
            content: const Text(
              'Combinar añade las sesiones del archivo a tu historial sin '
              'duplicar las que ya tienes. Reemplazar borra tu historial '
              'actual y deja solo lo del archivo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, 'replace'),
                child: const Text('Reemplazar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'merge'),
                child: const Text('Combinar'),
              ),
            ],
          ),
        );
        if (mode == null) return;
        final replace = mode == 'replace';

        final isJson = (result.single.extension ?? '').toLowerCase() == 'json';
        final report = isJson
            ? await StatsRepository.importJson(content, replace: replace)
            : await StatsRepository.importCsv(content, replace: replace);
        if (!mounted) return;
        setState(() => _future = _loadData());
        final omitted = report.skipped > 0
            ? ' (${report.skipped} omitidas: repetidas o no válidas)'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sesiones importadas: ${report.added}$omitted')),
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
              } else if (value == 'history') {
                await _openHistory();
              } else if (value == 'import') {
                await _import();
              } else if (value == 'clear') {
                await _confirmClear();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'history',
                child: Text('Historial de sesiones'),
              ),
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

  /// Abre el historial y, al volver, recarga por si se editó algo.
  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
    if (!mounted) return;
    setState(() => _future = _loadData());
  }

  void _showBarInfo(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, DayStats> data,
    List<SessionRecord> sessionsList,
    PomodoroSettings settings,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final goal = settings.dailyGoal;
    final numDays = _period == StatsPeriod.week ? 7 : 30;

    // `_offset` retrocede de período en período (0 = últimos 7 / 30 días).
    final endDay = DateTime(now.year, now.month, now.day - _offset * numDays);
    final days = List.generate(
      numDays,
      (i) => DateTime(endDay.year, endDay.month, endDay.day - (numDays - 1 - i)),
    );
    final stats = [
      for (final d in days) data[StatsRepository.dayKey(d)] ?? const DayStats(),
    ];

    final todayStats = data[StatsRepository.dayKey(now)] ?? const DayStats();
    final totalSessions = stats.fold<int>(0, (sum, s) => sum + s.sessions);
    final totalMinutes = stats.fold<int>(0, (sum, s) => sum + s.minutes);
    final activeDays = stats.where((s) => s.sessions > 0).length;
    final avgPerActiveDay = activeDays == 0 ? 0.0 : totalSessions / activeDays;

    final currentStreak = StatsRepository.calculateStreak(data);
    final bestStreak = StatsRepository.calculateBestStreak(data);
    final bestDayEntry = StatsRepository.getBestDay(data);
    final bestSlot = StatsRepository.getMostProductiveTimeSlot(sessionsList);
    final achievements = Achievement.evaluate(sessionsList, data);
    final hasAny = sessionsList.isNotEmpty;

    final rangeStart = days.first;
    final rangeEnd = DateTime(endDay.year, endDay.month, endDay.day + 1);
    final canGoBack = sessionsList.any((s) => s.timestamp.isBefore(rangeStart));

    final Map<String, ({int sessions, int minutes})> tagStats = {};
    for (final s in sessionsList) {
      if (s.timestamp.isBefore(rangeStart) || !s.timestamp.isBefore(rangeEnd)) {
        continue;
      }
      final name = s.tag ?? 'Sin etiqueta';
      final current = tagStats[name] ?? (sessions: 0, minutes: 0);
      tagStats[name] = (
        sessions: current.sessions + 1,
        minutes: current.minutes + s.minutes,
      );
    }
    final tagEntries = tagStats.entries.toList()
      ..sort((a, b) => b.value.minutes.compareTo(a.value.minutes));
    final maxTagMinutes =
        tagEntries.isEmpty ? 1 : max(1, tagEntries.first.value.minutes);
    final palette = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
      scheme.outline,
    ];

    final rangeLabel = _offset == 0
        ? (_period == StatsPeriod.week ? 'Últimos 7 días' : 'Últimos 30 días')
        : '${_shortDate(days.first)} – ${_shortDate(days.last)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _TodayHero(
          done: todayStats.sessions,
          goal: goal,
          minutes: _formatMinutes(todayStats.minutes),
          streak: currentStreak,
          bestStreak: bestStreak,
        ),
        const SizedBox(height: 12),
        if (!hasAny)
          const _EmptyStats()
        else ...[
          Center(
            child: SegmentedButton<StatsPeriod>(
              segments: const [
                ButtonSegment(
                  value: StatsPeriod.week,
                  label: Text('Semana'),
                  icon: Icon(Icons.calendar_view_week),
                ),
                ButtonSegment(
                  value: StatsPeriod.month,
                  label: Text('Mes'),
                  icon: Icon(Icons.calendar_view_month),
                ),
              ],
              selected: {_period},
              onSelectionChanged: (set) => setState(() {
                _period = set.first;
                _offset = 0;
              }),
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Período anterior',
                onPressed: canGoBack ? () => setState(() => _offset++) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  rangeLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Período siguiente',
                onPressed: _offset == 0 ? null : () => setState(() => _offset--),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _MiniStat(label: 'Sesiones', value: '$totalSessions'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(label: 'Tiempo', value: _formatMinutes(totalMinutes)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Media/día activo',
                  value: avgPerActiveDay.toStringAsFixed(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Sesiones por día',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BarChart(
                  days: days,
                  stats: stats,
                  goal: goal,
                  compact: _period == StatsPeriod.month,
                  onTapBar: (i) => _showBarInfo(
                    '${_shortDate(days[i])}: ${stats[i].sessions} '
                    '${stats[i].sessions == 1 ? 'sesión' : 'sesiones'} '
                    '(${_formatMinutes(stats[i].minutes)})',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Línea punteada: tu meta diaria ($goal)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Constancia · 12 semanas',
            child: _Heatmap(data: data, goal: goal),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Tiempo por etiqueta',
            child: tagEntries.isEmpty
                ? Text(
                    'No hay sesiones en este período.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < tagEntries.length; i++) ...[
                        _TagRow(
                          name: tagEntries[i].key,
                          detail: '${tagEntries[i].value.sessions} '
                              '${tagEntries[i].value.sessions == 1 ? 'sesión' : 'sesiones'}'
                              ' · ${_formatMinutes(tagEntries[i].value.minutes)}',
                          fraction: tagEntries[i].value.minutes / maxTagMinutes,
                          color: palette[i % palette.length],
                        ),
                        if (i != tagEntries.length - 1) const SizedBox(height: 14),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Destacados',
            child: Column(
              children: [
                _InsightRow(
                  icon: Icons.emoji_events_outlined,
                  label: 'Mejor día',
                  value: bestDayEntry == null
                      ? 'Sin datos'
                      : '${_dateFromKey(bestDayEntry.key)} · '
                          '${bestDayEntry.value.sessions} sesiones',
                ),
                _InsightRow(
                  icon: Icons.schedule,
                  label: 'Franja más activa',
                  value: bestSlot,
                ),
                _InsightRow(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Mejor racha',
                  value: '$bestStreak ${bestStreak == 1 ? 'día' : 'días'}',
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _AchievementsCard(
          achievements: achievements,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AchievementsPage(
                sessions: sessionsList,
                stats: data,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _LinkCard(
          icon: Icons.history,
          title: 'Historial de sesiones',
          subtitle: 'Ver, editar, añadir o borrar sesiones y notas',
          onTap: _openHistory,
        ),
      ],
    );
  }
}

const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// 'yyyy-mm-dd' -> '9 oct 2026'.
String _dateFromKey(String key) {
  final p = key.split('-');
  if (p.length != 3) return key;
  final month = int.tryParse(p[1]) ?? 1;
  final idx = month < 1 ? 0 : (month > 12 ? 11 : month - 1);
  return '${int.tryParse(p[2]) ?? 1} ${_months[idx]} ${p[0]}';
}

/// Tarjeta de resumen de hoy: progreso circular hacia la meta y racha.
class _TodayHero extends StatelessWidget {
  const _TodayHero({
    required this.done,
    required this.goal,
    required this.minutes,
    required this.streak,
    required this.bestStreak,
  });

  final int done;
  final int goal;
  final String minutes;
  final int streak;
  final int bestStreak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final value = goal <= 0 ? 0.0 : (done / goal).clamp(0.0, 1.0).toDouble();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: value),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => CircularProgressIndicator(
                        value: v,
                        strokeWidth: 9,
                        color: scheme.primary,
                        backgroundColor:
                            scheme.onPrimaryContainer.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$done',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        'de $goal',
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hoy',
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    minutes,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 18,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Racha $streak ${streak == 1 ? 'día' : 'días'} · mejor $bestStreak',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStats extends StatelessWidget {
  const _EmptyStats();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.timer_outlined, size: 40, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'Aún no hay sesiones',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Completa tu primer pomodoro y aquí verás tu progreso, tu racha y tus mejores días.',
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
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.name,
    required this.detail,
    required this.fraction,
    required this.color,
  });

  final String name;
  final String detail;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              detail,
              style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0).toDouble(),
            minHeight: 6,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: scheme.primary),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({required this.achievements, required this.onTap});

  final List<Achievement> achievements;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final unlocked = achievements.where((a) => a.unlocked).length;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Logros',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$unlocked de ${achievements.length} desbloqueados',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final a in achievements)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: a.unlocked
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                      ),
                      child: Icon(
                        a.icon,
                        size: 22,
                        color: a.unlocked
                            ? scheme.onPrimaryContainer
                            : scheme.outline,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barras por día con la meta como línea punteada.
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.days,
    required this.stats,
    required this.goal,
    required this.compact,
    required this.onTapBar,
  });

  final List<DateTime> days;
  final List<DayStats> stats;
  final int goal;
  final bool compact;
  final void Function(int index) onTapBar;

  static const double _area = 120;
  static const double _labelH = 22;
  static const _weekdayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = stats.fold<int>(0, (a, s) => max(a, s.sessions));
    final maxV = max(max(goal, peak), 1).toDouble();
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final goalY = _labelH + _area * goal / maxV;

    return SizedBox(
      height: _area + _labelH + 20,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: goalY,
            child: SizedBox(
              height: 1,
              child: CustomPaint(painter: _DashedLinePainter(scheme.outline)),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(child: _bar(context, i, maxV, todayDate)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, int i, double maxV, DateTime todayDate) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final count = stats[i].sessions;
    final d = days[i];
    final isToday = d == todayDate;

    final Color color;
    if (isToday) {
      color = scheme.primary;
    } else if (count == 0) {
      color = scheme.surfaceContainerHighest;
    } else if (count >= goal) {
      color = scheme.tertiary;
    } else {
      color = scheme.secondary.withValues(alpha: 0.55);
    }

    final label = compact
        ? ((i % 5 == 0 || i == days.length - 1) ? '${d.day}' : '')
        : _weekdayLabels[d.weekday - 1];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTapBar(i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!compact && count > 0)
            Text(
              '$count',
              style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: compact ? 6 : 22,
            height: count == 0 ? 3 : max(4.0, _area * count / maxV),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(compact ? 3 : 7),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: _labelH - 6,
            child: Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + 5, 0), paint);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

/// Mapa de calor de las últimas 12 semanas (columnas = semanas, filas = L..D).
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.data, required this.goal});

  final Map<String, DayStats> data;
  final int goal;

  static const int _weeks = 12;
  static const double _cell = 18;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final start = DateTime(monday.year, monday.month, monday.day - 7 * (_weeks - 1));
    final safeGoal = max(1, goal);

    Color colorFor(int sessions) => sessions == 0
        ? scheme.surfaceContainerHighest
        : scheme.primary.withValues(alpha: 0.3 + 0.7 * min(1.0, sessions / safeGoal));

    Widget cell(DateTime date) {
      if (date.isAfter(today)) {
        return const Padding(
          padding: EdgeInsets.all(2),
          child: SizedBox(width: _cell, height: _cell),
        );
      }
      final sessions = data[StatsRepository.dayKey(date)]?.sessions ?? 0;
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Tooltip(
          message: '${_shortDate(date)} · $sessions',
          child: Container(
            width: _cell,
            height: _cell,
            decoration: BoxDecoration(
              color: colorFor(sessions),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var w = 0; w < _weeks; w++)
              Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    cell(DateTime(start.year, start.month, start.day + w * 7 + d)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Menos',
              style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            for (final level in const [0, 1, 2, 3, 4])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: level == 0
                        ? scheme.surfaceContainerHighest
                        : scheme.primary.withValues(alpha: 0.3 + 0.7 * level / 4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              'Más',
              style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}
