// lib/main.dart
import 'package:aitube2/services/settings_service.dart';
import 'package:aitube2/services/websocket_api_service.dart';
import 'package:aitube2/theme/colors.dart';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

    // Initialize services
  await Future.wait([
    SettingsService().initialize(), 
    CacheService().initialize(),
    WebSocketApiService().initialize(),
  ]);

  runApp(const AiTubeApp());
}

class AiTubeApp extends StatelessWidget {
  const AiTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AiTube',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          surface: AiTubeColors.surface,
          surfaceContainerHighest: AiTubeColors.surfaceVariant,
          primary: AiTubeColors.primary,
          onSurface: AiTubeColors.onSurface,
          onSurfaceVariant: AiTubeColors.onSurfaceVariant,
        ),
        scaffoldBackgroundColor: AiTubeColors.background,
        cardTheme: CardTheme(
          color: AiTubeColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AiTubeColors.background,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: AiTubeColors.onBackground),
          titleMedium: TextStyle(color: AiTubeColors.onBackground),
          bodyLarge: TextStyle(color: AiTubeColors.onSurface),
          bodyMedium: TextStyle(color: AiTubeColors.onSurfaceVariant),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          surface: AiTubeColors.surface,
          surfaceContainerHighest: AiTubeColors.surfaceVariant,
          primary: AiTubeColors.primary,
          onSurface: AiTubeColors.onSurface,
          onSurfaceVariant: AiTubeColors.onSurfaceVariant,
        ),
        scaffoldBackgroundColor: AiTubeColors.background,
        cardTheme: CardTheme(
          color: AiTubeColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AiTubeColors.background,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: AiTubeColors.onBackground),
          titleMedium: TextStyle(color: AiTubeColors.onBackground),
          bodyLarge: TextStyle(color: AiTubeColors.onSurface),
          bodyMedium: TextStyle(color: AiTubeColors.onSurfaceVariant),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}