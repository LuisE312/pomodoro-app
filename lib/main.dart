import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

import 'app_shell.dart';
import 'notification_service.dart';
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

  static const _seed = Colors.red;

  @override
  Widget build(BuildContext context) {
    // Los colores dinámicos vienen nulos si el teléfono no los soporta.
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final light =
            lightDynamic ?? ColorScheme.fromSeed(seedColor: _seed);
        final dark = darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: _seed,
              brightness: Brightness.dark,
            );
        return MaterialApp(
          title: 'Pomodoro',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: light, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
          themeMode: ThemeMode.system,
          home: AppShell(controller: controller),
        );
      },
    );
  }
}