import 'package:flutter/material.dart';

class ThemePreset {
  final String name;
  final Color seedColor;
  const ThemePreset({required this.name, required this.seedColor});
}

const List<ThemePreset> kThemePresets = [
  ThemePreset(name: 'Purple', seedColor: Color(0xFF667eea)),
  ThemePreset(name: 'Professional Blue', seedColor: Color(0xFF1D4ED8)),
  ThemePreset(name: 'Forest', seedColor: Color(0xFF22c55e)),
  ThemePreset(name: 'Sunset', seedColor: Color(0xFFf97316)),
  ThemePreset(name: 'Rose', seedColor: Color(0xFFec4899)),
  ThemePreset(name: 'Slate', seedColor: Color(0xFF64748b)),
];

class CustomPreset {
  final String name;
  final Color seedColor;
  final Map<String, Color> customColors;

  const CustomPreset({
    required this.name,
    required this.seedColor,
    this.customColors = const {},
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'seedColor': seedColor.toARGB32().toRadixString(16),
        'customColors':
            customColors.map((k, v) => MapEntry(k, v.toARGB32().toRadixString(16))),
      };

  factory CustomPreset.fromJson(Map<String, dynamic> json) {
    final colorsRaw = json['customColors'] as Map<String, dynamic>? ?? {};
    return CustomPreset(
      name: json['name'] as String,
      seedColor: Color(int.parse(json['seedColor'] as String, radix: 16)),
      customColors: colorsRaw.map(
        (k, v) => MapEntry(k, Color(int.parse(v as String, radix: 16))),
      ),
    );
  }
}

class ThemeSettings {
  final Color seedColor;
  final ThemeMode mode;
  final Map<String, Color> customColors;

  const ThemeSettings({
    this.seedColor = const Color(0xFF8B7BFF), // Midnight Violet accent
    this.mode = ThemeMode.system,
    this.customColors = const {},
  });

  ThemeSettings copyWith({
    Color? seedColor,
    ThemeMode? mode,
    Map<String, Color>? customColors,
  }) {
    return ThemeSettings(
      seedColor: seedColor ?? this.seedColor,
      mode: mode ?? this.mode,
      customColors: customColors ?? this.customColors,
    );
  }
}
