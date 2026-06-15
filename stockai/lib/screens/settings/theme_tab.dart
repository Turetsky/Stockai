part of '../settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Theme Tab
// ─────────────────────────────────────────────────────────────────────────────

class _ThemeTab extends StatefulWidget {
  const _ThemeTab();

  @override
  State<_ThemeTab> createState() => _ThemeTabState();
}

class _ThemeTabState extends State<_ThemeTab> {
  final _supabaseService = SupabaseService();
  final _presetNameController = TextEditingController();
  bool _savingPreset = false;

  @override
  void dispose() {
    _presetNameController.dispose();
    super.dispose();
  }

  Future<void> _setMode(ThemeMode mode) async {
    themeNotifier.value = themeNotifier.value.copyWith(mode: mode);
    final s = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    try {
      await _supabaseService.setUiSetting('theme_mode', s);
    } catch (_) {}
  }

  Future<void> _setSeedColor(Color color) async {
    themeNotifier.value = themeNotifier.value.copyWith(seedColor: color);
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    try {
      await _supabaseService.setUiSetting('theme_color', hex);
    } catch (_) {}
  }

  Future<void> _setCustomColor(String key, Color? color) async {
    final current = themeNotifier.value;
    final newColors = Map<String, Color>.from(current.customColors);
    if (color == null) {
      newColors.remove(key);
    } else {
      newColors[key] = color;
    }
    themeNotifier.value = current.copyWith(customColors: newColors);

    final dbKey = switch (key) {
      'background' => 'bg_color',
      'cards' => 'card_color',
      'accent' => 'accent_color',
      _ => null,
    };
    if (dbKey == null) return;

    final hex = color != null
        ? '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
        : '';
    try {
      await _supabaseService.setUiSetting(dbKey, hex);
    } catch (_) {}
  }

  Future<void> _savePreset() async {
    final name = _presetNameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingPreset = true);
    try {
      final current = themeNotifier.value;
      final preset = CustomPreset(
        name: name,
        seedColor: current.seedColor,
        customColors: Map<String, Color>.from(current.customColors),
      );
      final newPresets = [...customPresetsNotifier.value, preset];
      customPresetsNotifier.value = newPresets;
      final json = jsonEncode(newPresets.map((p) => p.toJson()).toList());
      await _supabaseService.setUiSetting('custom_presets', json);
      _presetNameController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingPreset = false);
    }
  }

  Future<void> _loadPreset(CustomPreset preset) async {
    themeNotifier.value = ThemeSettings(
      seedColor: preset.seedColor,
      mode: themeNotifier.value.mode,
      customColors: Map<String, Color>.from(preset.customColors),
    );
    final hex = '#${preset.seedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    try {
      await _supabaseService.setUiSetting('theme_color', hex);
      const keyMap = {
        'background': 'bg_color',
        'cards': 'card_color',
        'accent': 'accent_color',
      };
      for (final entry in keyMap.entries) {
        final c = preset.customColors[entry.key];
        final val = c != null
            ? '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
            : '';
        await _supabaseService.setUiSetting(entry.value, val);
      }
    } catch (_) {}
  }

  Future<void> _deletePreset(CustomPreset preset) async {
    final newPresets =
        customPresetsNotifier.value.where((p) => p.name != preset.name).toList();
    customPresetsNotifier.value = newPresets;
    try {
      final json = jsonEncode(newPresets.map((p) => p.toJson()).toList());
      await _supabaseService.setUiSetting('custom_presets', json);
    } catch (_) {}
  }

  Future<Color?> _showColorPicker(Color current, String label) {
    Color picked = current;
    return showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Pick $label Color'),
          content: SizedBox(
            width: 280,
            child: HueRingPicker(
              pickerColor: picked,
              onColorChanged: (c) => setDialogState(() => picked = c),
              enableAlpha: false,
              displayThumbColor: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, picked),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(Color color, String name, bool isSelected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, color: Colors.white, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorRow(
    BuildContext context, {
    required String label,
    required Color previewColor,
    required bool hasOverride,
    required VoidCallback onTap,
    VoidCallback? onReset,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: previewColor,
                borderRadius: BorderRadius.circular(10),
                border: !hasOverride
                    ? Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.4),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    hasOverride
                        ? '#${previewColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
                        : 'Auto from theme',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onReset != null)
              IconButton(
                icon: Icon(
                  Icons.restart_alt,
                  size: 20,
                  color: Theme.of(context).colorScheme.outline,
                ),
                tooltip: 'Reset to auto',
                onPressed: onReset,
              )
            else
              const SizedBox(width: 48),
            Icon(Icons.chevron_right,
                color: Theme.of(context).colorScheme.outline),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeSettings>(
      valueListenable: themeNotifier,
      builder: (context, settings, _) {
        return ValueListenableBuilder<List<CustomPreset>>(
          valueListenable: customPresetsNotifier,
          builder: (context, customPresets, _) {
            // Compute scheme for preview fallback colors
            final isDark = settings.mode == ThemeMode.dark ||
                (settings.mode == ThemeMode.system &&
                    MediaQuery.platformBrightnessOf(context) == Brightness.dark);
            final scheme = ColorScheme.fromSeed(
              seedColor: settings.seedColor,
              brightness: isDark ? Brightness.dark : Brightness.light,
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Mode ──
                Text('Mode', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: (s) => _setMode(s.first),
                ),

                // ── Built-in Presets ──
                const SizedBox(height: 24),
                Text('Presets', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.2,
                  children: kThemePresets.map((preset) {
                    final isSelected =
                        settings.seedColor.toARGB32() == preset.seedColor.toARGB32() &&
                            settings.customColors.isEmpty;
                    return _presetChip(
                      preset.seedColor,
                      preset.name,
                      isSelected,
                      () => _setSeedColor(preset.seedColor),
                    );
                  }).toList(),
                ),

                // ── Custom Presets ──
                if (customPresets.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Saved',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.2,
                    children: customPresets.map((preset) {
                      final isSelected = settings.seedColor.toARGB32() ==
                          preset.seedColor.toARGB32();
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: _presetChip(
                              preset.seedColor,
                              preset.name,
                              isSelected,
                              () => _loadPreset(preset),
                            ),
                          ),
                          Positioned(
                            top: -5,
                            right: -5,
                            child: GestureDetector(
                              onTap: () => _deletePreset(preset),
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],

                // ── Customize ──
                const SizedBox(height: 24),
                Text('Customize',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Tap an element to change its color.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),

                _colorRow(
                  context,
                  label: 'Primary',
                  previewColor: settings.seedColor,
                  hasOverride: true,
                  onTap: () async {
                    final picked =
                        await _showColorPicker(settings.seedColor, 'Primary');
                    if (picked != null) _setSeedColor(picked);
                  },
                ),
                _colorRow(
                  context,
                  label: 'Background',
                  previewColor: settings.customColors['background'] ?? scheme.surface,
                  hasOverride: settings.customColors.containsKey('background'),
                  onTap: () async {
                    final current =
                        settings.customColors['background'] ?? scheme.surface;
                    final picked =
                        await _showColorPicker(current, 'Background');
                    if (picked != null) _setCustomColor('background', picked);
                  },
                  onReset: settings.customColors.containsKey('background')
                      ? () => _setCustomColor('background', null)
                      : null,
                ),
                _colorRow(
                  context,
                  label: 'Cards',
                  previewColor:
                      settings.customColors['cards'] ?? scheme.surfaceContainer,
                  hasOverride: settings.customColors.containsKey('cards'),
                  onTap: () async {
                    final current =
                        settings.customColors['cards'] ?? scheme.surfaceContainer;
                    final picked = await _showColorPicker(current, 'Cards');
                    if (picked != null) _setCustomColor('cards', picked);
                  },
                  onReset: settings.customColors.containsKey('cards')
                      ? () => _setCustomColor('cards', null)
                      : null,
                ),
                _colorRow(
                  context,
                  label: 'Accent',
                  previewColor:
                      settings.customColors['accent'] ?? scheme.secondary,
                  hasOverride: settings.customColors.containsKey('accent'),
                  onTap: () async {
                    final current =
                        settings.customColors['accent'] ?? scheme.secondary;
                    final picked = await _showColorPicker(current, 'Accent');
                    if (picked != null) _setCustomColor('accent', picked);
                  },
                  onReset: settings.customColors.containsKey('accent')
                      ? () => _setCustomColor('accent', null)
                      : null,
                ),

                // ── Save as Preset ──
                const SizedBox(height: 24),
                Text('Save as Preset',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _presetNameController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Preset name',
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _savePreset(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _savingPreset ? null : _savePreset,
                      child: _savingPreset
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        );
      },
    );
  }
}
