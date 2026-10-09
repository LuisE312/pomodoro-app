import 'package:material_ui/material_ui.dart';
import 'stats.dart';

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final bool unlocked;

  static List<Achievement> evaluate(
      List<SessionRecord> sessions, Map<String, DayStats> stats) {
    final totalSessions = sessions.length;
    final currentStreak = StatsRepository.calculateStreak(stats);
    final bestStreak = StatsRepository.calculateBestStreak(stats);
    final maxStreak = bestStreak > currentStreak ? bestStreak : currentStreak;

    return [
      Achievement(
        id: 'first_session',
        title: 'Primera sesión',
        description: 'Completa tu primer pomodoro',
        icon: Icons.star,
        unlocked: totalSessions >= 1,
      ),
      Achievement(
        id: 'streak_3',
        title: 'Constancia de 3 días',
        description: 'Alcanza una racha de 3 días seguidos',
        icon: Icons.local_fire_department,
        unlocked: maxStreak >= 3,
      ),
      Achievement(
        id: 'streak_7',
        title: 'Una semana entera',
        description: 'Alcanza una racha de 7 días seguidos',
        icon: Icons.whatshot,
        unlocked: maxStreak >= 7,
      ),
      Achievement(
        id: 'streak_30',
        title: 'Maestro del hábito',
        description: 'Alcanza una racha de 30 días seguidos',
        icon: Icons.military_tech,
        unlocked: maxStreak >= 30,
      ),
      Achievement(
        id: 'sessions_100',
        title: 'Centurión',
        description: 'Completa 100 sesiones de enfoque',
        icon: Icons.emoji_events,
        unlocked: totalSessions >= 100,
      ),
    ];
  }
}

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({
    super.key,
    required this.sessions,
    required this.stats,
  });

  final List<SessionRecord> sessions;
  final Map<String, DayStats> stats;

  @override
  Widget build(BuildContext context) {
    final achievements = Achievement.evaluate(sessions, stats);
    final unlockedCount = achievements.where((a) => a.unlocked).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logros'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, size: 40, color: Colors.amber),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progreso de logros',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$unlockedCount de ${achievements.length} desbloqueados',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final a in achievements)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: a.unlocked
                  ? null
                  : Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: a.unlocked
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    a.icon,
                    color: a.unlocked
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
                title: Text(
                  a.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: a.unlocked
                        ? null
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
                subtitle: Text(a.description),
                trailing: Icon(
                  a.unlocked ? Icons.check_circle : Icons.lock_outline,
                  color: a.unlocked
                      ? Colors.green
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
