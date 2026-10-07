import 'package:flutter/material.dart';

/// Las tres fases posibles del ciclo.
enum PomodoroPhase {
  focus(label: 'Enfoque', color: Colors.red),
  shortBreak(label: 'Descanso corto', color: Colors.green),
  longBreak(label: 'Descanso largo', color: Colors.blue);

  const PomodoroPhase({required this.label, required this.color});

  final String label;
  final Color color;
}