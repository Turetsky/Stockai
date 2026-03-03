import 'package:flutter/material.dart';

class ThemePreset {
  final String name;
  final Color seedColor;
  const ThemePreset({required this.name, required this.seedColor});
}

const List<ThemePreset> kThemePresets = [
  ThemePreset(name: 'Purple', seedColor: Color(0xFF667eea)),
  ThemePreset(name: 'Ocean', seedColor: Color(0xFF0ea5e9)),
  ThemePreset(name: 'Forest', seedColor: Color(0xFF22c55e)),
  ThemePreset(name: 'Sunset', seedColor: Color(0xFFf97316)),
  ThemePreset(name: 'Rose', seedColor: Color(0xFFec4899)),
  ThemePreset(name: 'Slate', seedColor: Color(0xFF64748b)),
];

class ThemeSettings {
  final Color seedColor;
  final ThemeMode mode;

  const ThemeSettings({
    this.seedColor = const Color(0xFF667eea),
    this.mode = ThemeMode.system,
  });

  ThemeSettings copyWith({Color? seedColor, ThemeMode? mode}) {
    return ThemeSettings(
      seedColor: seedColor ?? this.seedColor,
      mode: mode ?? this.mode,
    );
  }
}
