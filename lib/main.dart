import 'package:flutter/material.dart';

import 'pomodoro_page.dart';
import 'settings.dart';

Future<void> main() async {
  // Necesario para usar plugins antes de arrancar la app.
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await PomodoroSettings.load();
  runApp(PomodoroApp(initialSettings: settings));
}

class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key, required this.initialSettings});

  final PomodoroSettings initialSettings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pomodoro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: PomodoroPage(initialSettings: initialSettings),
    );
  }
}