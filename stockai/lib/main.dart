import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/theme_settings.dart';
import 'services/supabase_service.dart';
import 'screens/splash_screen.dart';
import 'theme/app_style.dart';

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

    Color seedColor = AppStyle.brandAccent; // Midnight Violet default
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
    final lightSurface = bgOverride ?? Color.lerp(scheme.surface, seedColor, 0.08)!;
    return ThemeData(
      colorScheme: scheme.copyWith(
        surface: lightSurface,
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
      // Pin the AppBar to the body surface and disable the M3 scrolled-under
      // tint/elevation. Otherwise a scrolled-under AppBar defaults to
      // colorScheme.surfaceContainer (the white card_color override), which
      // makes the header mismatch the body. See chat-header white-bg bug.
      appBarTheme: AppBarTheme(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      useMaterial3: true,
    );
  }
  // "Midnight Violet" dark brand baseline (shared with the web app). Uses the
  // exact brand palette; light-authored bg/card overrides are intentionally
  // NOT applied here (see white-header fix) so the brand renders consistently.
  const darkSurface = AppStyle.brandBg; // #07070E
  const darkPanel = AppStyle.brandSurface; // #0D0D18
  final darkElevated = Color.lerp(darkPanel, Colors.white, 0.05)!;
  return ThemeData(
    colorScheme: scheme.copyWith(
      surface: darkSurface,
      surfaceContainerLowest: const Color(0xFF050509),
      surfaceContainerLow: darkPanel,
      surfaceContainer: darkPanel,
      surfaceContainerHigh: darkElevated,
      surfaceContainerHighest: darkElevated,
      onSurface: AppStyle.textPrimary,
      onSurfaceVariant: AppStyle.textSecondary,
      outline: Colors.white.withValues(alpha: 0.12),
      outlineVariant: Colors.white.withValues(alpha: 0.08),
      secondary: accentOverride,
      tertiary: accentOverride != null
          ? Color.lerp(accentOverride, Colors.black, 0.2)
          : null,
    ),
    scaffoldBackgroundColor: darkSurface,
    appBarTheme: AppBarTheme(
      backgroundColor: darkSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    // Brand component themes — propagate the glass/hairline look to Cards,
    // inputs and dividers across all screens (settings, category, dialogs)
    // without per-widget styling.
    cardTheme: CardThemeData(
      color: darkPanel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppStyle.rCard),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.08),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
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
          title: 'StockAI',
          debugShowCheckedModeBanner: false,
          themeMode: settings.mode,
          theme: _buildTheme(settings.seedColor, Brightness.light, settings.customColors),
          darkTheme: _buildTheme(settings.seedColor, Brightness.dark, settings.customColors),
          home: const SplashScreen(),
        );
      },
    );
  }
}
