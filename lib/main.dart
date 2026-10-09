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

  ThemeMode _flutterThemeMode(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.settings;
        final themeMode = _flutterThemeMode(settings.themeMode);

        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final lightScheme =
                lightDynamic ?? ColorScheme.fromSeed(seedColor: _seed);
            var darkScheme = darkDynamic ??
                ColorScheme.fromSeed(
                  seedColor: _seed,
                  brightness: Brightness.dark,
                );

            if (settings.amoledMode) {
              darkScheme = darkScheme.copyWith(
                surface: Colors.black,
                onSurface: Colors.white,
              );
            }

            final darkTheme = ThemeData(
              colorScheme: darkScheme,
              useMaterial3: true,
              scaffoldBackgroundColor:
                  settings.amoledMode ? Colors.black : null,
            );

            return MaterialApp(
              title: 'Pomodoro',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
              darkTheme: darkTheme,
              themeMode: themeMode,
              home: AppShell(controller: controller),
            );
          },
        );
      },
    );
  }
}