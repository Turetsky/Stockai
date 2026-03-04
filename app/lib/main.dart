import 'dart:convert';
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
final customPresetsNotifier = ValueNotifier<List<CustomPreset>>([]);

Future<void> loadThemeFromSupabase() async {
  try {
    final settings = await SupabaseService().getUiSettings();

    Color seedColor = const Color(0xFF667eea);
    ThemeMode mode = ThemeMode.system;
    final customColors = <String, Color>{};
    var customPresets = <CustomPreset>[];

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

    const colorKeys = {
      'background': 'bg_color',
      'cards': 'card_color',
      'accent': 'accent_color',
    };
    for (final entry in colorKeys.entries) {
      if (settings.containsKey(entry.value)) {
        final hex = settings[entry.value]!.replaceAll('#', '');
        if (hex.length == 6) {
          customColors[entry.key] = Color(int.parse('FF$hex', radix: 16));
        }
      }
    }

    if (settings.containsKey('custom_presets')) {
      try {
        final raw = jsonDecode(settings['custom_presets']!) as List;
        customPresets = raw
            .map((p) => CustomPreset.fromJson(p as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    themeNotifier.value = ThemeSettings(
      seedColor: seedColor,
      mode: mode,
      customColors: customColors,
    );
    customPresetsNotifier.value = customPresets;
  } catch (_) {
    // Keep defaults on error
  }
}

ThemeData _buildTheme(
  Color seedColor,
  Brightness brightness,
  Map<String, Color> customColors,
) {
  final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  final bgOverride = customColors['background'];
  final cardOverride = customColors['cards'];
  final accentOverride = customColors['accent'];

  if (brightness == Brightness.light) {
    return ThemeData(
      colorScheme: scheme.copyWith(
        surface: bgOverride ?? Color.lerp(scheme.surface, seedColor, 0.08)!,
        surfaceContainerLowest: bgOverride != null
            ? Color.lerp(bgOverride, Colors.white, 0.15)!
            : Color.lerp(scheme.surfaceContainerLowest, seedColor, 0.05)!,
        surfaceContainerLow: bgOverride != null
            ? Color.lerp(bgOverride, Colors.white, 0.07)!
            : Color.lerp(scheme.surfaceContainerLow, seedColor, 0.09)!,
        surfaceContainer:
            cardOverride ?? Color.lerp(scheme.surfaceContainer, seedColor, 0.11)!,
        surfaceContainerHigh: cardOverride != null
            ? Color.lerp(cardOverride, Colors.black, 0.05)!
            : Color.lerp(scheme.surfaceContainerHigh, seedColor, 0.13)!,
        surfaceContainerHighest: cardOverride != null
            ? Color.lerp(cardOverride, Colors.black, 0.10)!
            : Color.lerp(scheme.surfaceContainerHighest, seedColor, 0.15)!,
        secondary: accentOverride,
        secondaryContainer: accentOverride != null
            ? Color.lerp(accentOverride, Colors.white, 0.7)
            : null,
        tertiary: accentOverride != null
            ? Color.lerp(accentOverride, Colors.white, 0.2)
            : null,
      ),
      useMaterial3: true,
    );
  }
  return ThemeData(
    colorScheme: scheme.copyWith(
      surfaceContainer: cardOverride,
      secondary: accentOverride,
      tertiary: accentOverride != null
          ? Color.lerp(accentOverride, Colors.black, 0.2)
          : null,
    ),
    useMaterial3: true,
  );
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
          theme: _buildTheme(settings.seedColor, Brightness.light, settings.customColors),
          darkTheme: _buildTheme(settings.seedColor, Brightness.dark, settings.customColors),
          home: supabase.auth.currentSession != null
              ? const ChatScreen()
              : const LoginScreen(),
        );
      },
    );
  }
}
