import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/theme_settings.dart';
import 'services/supabase_service.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://masngvxdbxqrrreszjxv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1hc25ndnhkYnhxcnJyZXN6anh2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3Njc5MzIsImV4cCI6MjA4NjM0MzkzMn0.QmHFsyeMUkwE7cW6N88k2eSk2BpyXit2UxVlqXxl4zE',
  );

  runApp(const InventoryManagerApp());
}

final supabase = Supabase.instance.client;

final themeNotifier = ValueNotifier<ThemeSettings>(const ThemeSettings());

Future<void> loadThemeFromSupabase() async {
  try {
    final settings = await SupabaseService().getUiSettings();

    Color seedColor = const Color(0xFF667eea);
    ThemeMode mode = ThemeMode.system;

    if (settings.containsKey('theme_color')) {
      final hex = settings['theme_color']!.replaceAll('#', '');
      if (hex.length == 6) {
        seedColor = Color(int.parse('FF$hex', radix: 16));
      }
    }

    if (settings.containsKey('theme_mode')) {
      switch (settings['theme_mode']) {
        case 'light':
          mode = ThemeMode.light;
        case 'dark':
          mode = ThemeMode.dark;
        default:
          mode = ThemeMode.system;
      }
    }

    themeNotifier.value = ThemeSettings(seedColor: seedColor, mode: mode);
  } catch (_) {
    // Keep defaults on error
  }
}

ThemeData _buildTheme(Color seedColor, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  // In light mode, tint all surface layers with the seed color so the chosen
  // palette is visible without going full dark.
  if (brightness == Brightness.light) {
    return ThemeData(
      colorScheme: scheme.copyWith(
        surface: Color.lerp(scheme.surface, seedColor, 0.05)!,
        surfaceContainerLowest:
            Color.lerp(scheme.surfaceContainerLowest, seedColor, 0.03)!,
        surfaceContainerLow:
            Color.lerp(scheme.surfaceContainerLow, seedColor, 0.06)!,
        surfaceContainer:
            Color.lerp(scheme.surfaceContainer, seedColor, 0.08)!,
        surfaceContainerHigh:
            Color.lerp(scheme.surfaceContainerHigh, seedColor, 0.10)!,
        surfaceContainerHighest:
            Color.lerp(scheme.surfaceContainerHighest, seedColor, 0.12)!,
      ),
      useMaterial3: true,
    );
  }
  return ThemeData(colorScheme: scheme, useMaterial3: true);
}

class InventoryManagerApp extends StatelessWidget {
  const InventoryManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeSettings>(
      valueListenable: themeNotifier,
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'Inventory Manager',
          debugShowCheckedModeBanner: false,
          themeMode: settings.mode,
          theme: _buildTheme(settings.seedColor, Brightness.light),
          darkTheme: _buildTheme(settings.seedColor, Brightness.dark),
          home: supabase.auth.currentSession != null
              ? const ChatScreen()
              : const LoginScreen(),
        );
      },
    );
  }
}
