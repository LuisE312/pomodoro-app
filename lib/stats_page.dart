import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'stats.dart';

/// Pantalla de estadísticas: resumen de hoy, de la semana y gráfico.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<Map<String, DayStats>> _future = StatsRepository.load();

  static const _weekdayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  String _formatMinutes(int m) {
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar estadísticas'),
        content: const Text(
          'Se eliminarán todos tus registros. Esta acción no se puede deshacer.',
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
    setState(() => _future = StatsRepository.load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Borrar estadísticas',
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, DayStats>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildContent(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, DayStats> data) {
    final now = DateTime.now();
    // Los últimos 7 días, del más antiguo al de hoy.
    final days = List.generate(
      7,
      (i) => DateTime(now.year, now.month, now.day - (6 - i)),
    );
    final stats = [
      for (final d in days) data[StatsRepository.dayKey(d)] ?? const DayStats(),
    ];

    final today = stats.last;
    final weekSessions = stats.fold<int>(0, (sum, s) => sum + s.sessions);
    final weekMinutes = stats.fold<int>(0, (sum, s) => sum + s.minutes);
    final maxSessions = max(1, stats.map((s) => s.sessions).reduce(max));
    final streak = StatsRepository.calculateStreak(data);
    final avgMinutes = weekSessions > 0 ? (weekMinutes / weekSessions).round() : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Hoy',
                sessions: today.sessions,
                time: _formatMinutes(today.minutes),
                icon: Icons.today,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'Últimos 7 días',
                sessions: weekSessions,
                time: _formatMinutes(weekMinutes),
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
                      const Icon(Icons.local_fire_department, color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Racha actual', style: Theme.of(context).textTheme.labelMedium),
                          Text(
                            '$streak ${streak == 1 ? 'día' : 'días'}',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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
                      const Icon(Icons.av_timer, color: Colors.teal, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Promedio / sesión', style: Theme.of(context).textTheme.labelMedium),
                          Text(
                            _formatMinutes(avgMinutes),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Sesiones por día',
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
                  label: _weekdayLabels[days[i].weekday - 1],
                  isToday: i == days.length - 1,
                  formattedMinutes: _formatMinutes(stats[i].minutes),
                ),
            ],
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
  });

  final String title;
  final int sessions;
  final String time;
  final IconData icon;

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
                Text(title, style: textTheme.labelLarge),
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
          ],
        ),
      ),
    );
  }
}

/// Una barra del gráfico semanal con información al tocar.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.count,
    required this.minutes,
    required this.maxCount,
    required this.label,
    required this.isToday,
    required this.formattedMinutes,
  });

  final int count;
  final int minutes;
  final int maxCount;
  final String label;
  final bool isToday;
  final String formattedMinutes;

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
            Text('$count'),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 28,
              height: count == 0 ? 4 : 100 * count / maxCount,
              decoration: BoxDecoration(
                color: isToday
                    ? colors.primary
                    : (count == 0 ? colors.surfaceContainerHighest : colors.secondary),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
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