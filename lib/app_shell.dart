import 'package:material_ui/material_ui.dart';

import 'history_page.dart';
import 'pomodoro_page.dart';
import 'pomodoro_phase.dart';
import 'settings_page.dart';
import 'stats.dart';
import 'stats_page.dart';
import 'timer_controller.dart';

/// Estructura principal: las tres secciones y la barra de navegación.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final TimerController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.sessionEvents.addListener(_onSessionEvent);
    // Si al arrancar ya se había recuperado una sesión, se anuncia en el
    // primer fotograma (antes no hay Scaffold donde mostrar el aviso).
    if (widget.controller.sessionEvents.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSessionEvent());
    }
  }

  @override
  void dispose() {
    widget.controller.sessionEvents.removeListener(_onSessionEvent);
    super.dispose();
  }

  /// Avisa de que se registró una sesión (con botón para añadir una nota) y
  /// de los logros que desbloqueó. Los avisos se encolan, no se pisan.
  void _onSessionEvent() {
    final event = widget.controller.sessionEvents.value;
    if (event == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text('Sesión de ${event.minutes} min registrada'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Añadir nota',
          onPressed: () => _addNote(event),
        ),
      ),
    );

    if (event.unlocked.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.emoji_events, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  event.unlocked.length == 1
                      ? 'Logro desbloqueado: ${event.unlocked.first.title}'
                      : 'Logros desbloqueados: '
                          '${event.unlocked.map((a) => a.title).join(', ')}',
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _addNote(SessionEvent event) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const NoteDialog(),
    );
    if (note == null) return;
    await StatsRepository.setNote(event.timestamp, note);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nota guardada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      PomodoroPage(controller: widget.controller),
      const StatsPage(),
      SettingsPage(controller: widget.controller),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
      ),
      // Solo esta parte escucha al controlador: las páginas no se reconstruyen.
      bottomNavigationBar: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          // Modo enfoque: sin barra mientras corre un enfoque, y solo en la
          // pestaña del temporizador (en otras pestañas siempre hay barra,
          // para no dejar al usuario atrapado).
          final hide = _index == 0 &&
              widget.controller.settings.immersiveFocus &&
              widget.controller.isRunning &&
              widget.controller.phase == PomodoroPhase.focus;

          return AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: hide
                ? const SizedBox(width: double.infinity)
                : NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.timer_outlined),
                        selectedIcon: Icon(Icons.timer),
                        label: 'Temporizador',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.bar_chart_outlined),
                        selectedIcon: Icon(Icons.bar_chart),
                        label: 'Estadísticas',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: 'Ajustes',
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
