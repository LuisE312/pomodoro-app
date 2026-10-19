import 'dart:async';

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

  // Si la app se abrió tocando un botón de la notificación de fin de fase
  // (p. ej. "Iniciar descanso"), se ejecuta ahora que el controlador existe.
  final launchAction = await NotificationService.instance.launchActionId();
  if (launchAction != null) {
    unawaited(controller.handleNotificationAction(launchAction));
  }
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
    // Solo escucha los ajustes: antes escuchaba al controlador entero y toda la
    // MaterialApp se reconstruía 4 veces por segundo mientras corría el reloj.
    return ValueListenableBuilder<PomodoroSettings>(
      valueListenable: controller.settingsListenable,
      builder: (context, settings, _) {
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
              // Negro puro de fondo y superficies casi negras para las tarjetas,
              // para que sigan distinguiéndose sin romper el efecto AMOLED.
              darkScheme = darkScheme.copyWith(
                surface: Colors.black,
                surfaceContainerLowest: Colors.black,
                surfaceContainerLow: const Color(0xFF0C0C0C),
                surfaceContainer: const Color(0xFF121212),
                surfaceContainerHigh: const Color(0xFF181818),
                surfaceContainerHighest: const Color(0xFF212121),
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