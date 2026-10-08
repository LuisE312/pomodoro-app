import 'package:material_ui/material_ui.dart';

enum PomodoroPhase {
  focus(label: 'Enfoque', icon: Icons.center_focus_strong_outlined),
  shortBreak(label: 'Descanso corto', icon: Icons.coffee_outlined),
  longBreak(label: 'Descanso largo', icon: Icons.self_improvement);

  const PomodoroPhase({required this.label, required this.icon});

  final String label;
  final IconData icon;

  /// Color principal de la fase, tomado del tema actual.
  Color colorIn(ColorScheme scheme) => switch (this) {
    PomodoroPhase.focus => scheme.primary,
    PomodoroPhase.shortBreak => scheme.tertiary,
    PomodoroPhase.longBreak => scheme.secondary,
  };

  /// Color legible para texto o iconos sobre [colorIn].
  Color onColorIn(ColorScheme scheme) => switch (this) {
    PomodoroPhase.focus => scheme.onPrimary,
    PomodoroPhase.shortBreak => scheme.onTertiary,
    PomodoroPhase.longBreak => scheme.onSecondary,
  };
}