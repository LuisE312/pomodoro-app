import 'package:flutter/material.dart';

import 'notification_service.dart';
import 'pomodoro_page.dart';
import 'settings.dart';
import 'timer_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  final settings = await PomodoroSettings.load();
  final controller = await TimerController.load(settings);
  runApp(PomodoroApp(controller: controller));
}

class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key, required this.controller});

  final TimerController controller;

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
      home: PomodoroPage(controller: controller),
    );
  }
}