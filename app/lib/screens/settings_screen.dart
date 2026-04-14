import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/theme_settings.dart';
import '../services/supabase_service.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nameController = TextEditingController();
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final user = supabase.auth.currentUser;
    _nameController.text =
        user?.userMetadata?['display_name'] ?? user?.email?.split('@')[0] ?? '';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    try {
      await supabase.auth.updateUser(UserAttributes(data: {'display_name': name}));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display name updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all your data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService().deleteAccount();
      await supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Theme'),
            Tab(text: 'Profile'),
            Tab(text: 'Data'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _ThemeTab(),
          _ProfileTab(
            nameController: _nameController,
            saving: _savingName,
            onSave: _saveName,
            onLogout: _logout,
            onDeleteAccount: _deleteAccount,
          ),
          const _DataTab(),
        ],
      ),
    );
  }
}

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

// ─────────────────────────────────────────────────────────────────────────────
// Profile Tab
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final TextEditingController nameController;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const _ProfileTab({
    required this.nameController,
    required this.saving,
    required this.onSave,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Display Name', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
            hintText: 'Your display name',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSave(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: saving ? null : onSave,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save Name'),
        ),
        const SizedBox(height: 24),
        Text('AI Voice', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const _VoiceSection(),
        const SizedBox(height: 24),
        Text('Password', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const _PasswordSection(),
        const SizedBox(height: 24),
        Text('Account', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.email),
          title: const Text('Email'),
          subtitle: Text(user?.email ?? ''),
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign Out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
          ),
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Danger Zone',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Permanently deletes your account and all your data.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onDeleteAccount,
          icon: const Icon(Icons.delete_forever),
          label: const Text('Delete Account'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice Section
// ─────────────────────────────────────────────────────────────────────────────

class _VoiceSection extends StatefulWidget {
  const _VoiceSection();

  @override
  State<_VoiceSection> createState() => _VoiceSectionState();
}

class _VoiceSectionState extends State<_VoiceSection> {
  static const _voices = [
    {'id': 'EXAVITQu4vr4xnSDxMaL', 'name': 'Sarah — Female, Mature'},
    {'id': 'FGY2WhTYpPnrIDTdsKH5', 'name': 'Laura — Female, Quirky'},
    {'id': 'Xb7hH8MSUJpSbSDYk0k2', 'name': 'Alice — Female, Clear'},
    {'id': 'XrExE9yKIg1WjnnlVkGX', 'name': 'Matilda — Female, Professional'},
    {'id': 'cgSgspJ2msm6clMCkdW9', 'name': 'Jessica — Female, Playful'},
    {'id': 'pFZP5JQG7iQjIQuC4Bku', 'name': 'Lily — Female, Velvety'},
    {'id': 'nPczCjzI2devNBz1zQrb', 'name': 'Brian — Male, Deep'},
    {'id': 'CwhRBWXzGAHq8TQ4Fs17', 'name': 'Roger — Male, Laid-Back'},
    {'id': 'IKne3meq5aSn9XLyUdCD', 'name': 'Charlie — Male, Confident'},
    {'id': 'TX3LPaxmHKxFdv7VOQHJ', 'name': 'Liam — Male, Energetic'},
    {'id': 'onwK4e9ZLuTAKqWW03F9', 'name': 'Daniel — Male, Broadcaster'},
    {'id': 'pNInz6obpgDQGcFmaJgB', 'name': 'Adam — Male, Firm'},
  ];

  final _supabaseService = SupabaseService();
  String _selectedVoiceId = 'EXAVITQu4vr4xnSDxMaL'; // Sarah — free tier
  double _stability = 0.5;
  double _similarityBoost = 0.75;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadVoiceSettings();
  }

  Future<void> _loadVoiceSettings() async {
    final settings = await _supabaseService.getUiSettings();
    if (!mounted) return;
    setState(() {
      final v = settings['tts_voice_id'];
      if (v != null && v.isNotEmpty) _selectedVoiceId = v;
      final stab = double.tryParse(settings['tts_stability'] ?? '');
      if (stab != null) _stability = stab.clamp(0.0, 1.0);
      final sim = double.tryParse(settings['tts_similarity_boost'] ?? '');
      if (sim != null) _similarityBoost = sim.clamp(0.0, 1.0);
      _loading = false;
    });
  }

  Future<void> _saveVoice(String voiceId) async {
    setState(() { _selectedVoiceId = voiceId; _saving = true; });
    await _supabaseService.setUiSetting('tts_voice_id', voiceId);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _saveStability(double val) async {
    setState(() => _stability = val);
    await _supabaseService.setUiSetting('tts_stability', val.toStringAsFixed(2));
  }

  Future<void> _saveSimilarity(double val) async {
    setState(() => _similarityBoost = val);
    await _supabaseService.setUiSetting(
        'tts_similarity_boost', val.toStringAsFixed(2));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedVoiceId,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.record_voice_over),
            suffixIcon: _saving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
          items: _voices
              .map((v) => DropdownMenuItem(
                    value: v['id'],
                    child: Text(v['name']!),
                  ))
              .toList(),
          onChanged: (id) { if (id != null) _saveVoice(id); },
        ),
        const SizedBox(height: 20),
        // Stability slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Stability', style: theme.textTheme.bodyMedium),
            Text(_stability.toStringAsFixed(2),
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.outline)),
          ],
        ),
        Slider(
          value: _stability,
          min: 0,
          max: 1,
          divisions: 20,
          onChangeEnd: _saveStability,
          onChanged: (v) => setState(() => _stability = v),
        ),
        // Similarity Boost slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Similarity Boost', style: theme.textTheme.bodyMedium),
            Text(_similarityBoost.toStringAsFixed(2),
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.outline)),
          ],
        ),
        Slider(
          value: _similarityBoost,
          min: 0,
          max: 1,
          divisions: 20,
          onChangeEnd: _saveSimilarity,
          onChanged: (v) => setState(() => _similarityBoost = v),
        ),
      ],
    );
  }
}

class _PasswordSection extends StatefulWidget {
  const _PasswordSection();

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  @override
  void dispose() {
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final newPass = _newController.text;
    final confirm = _confirmController.text;

    if (newPass.isEmpty) return;
    if (newPass.length < 6) {
      _show('Password must be at least 6 characters');
      return;
    }
    if (newPass != confirm) {
      _show('Passwords do not match');
      return;
    }

    setState(() => _saving = true);
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPass));
      _newController.clear();
      _confirmController.clear();
      _show('Password updated');
    } catch (e) {
      _show('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _newController,
          obscureText: _obscureNew,
          decoration: InputDecoration(
            labelText: 'New Password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon:
                  Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm ? Icons.visibility : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _changePassword(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _changePassword,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Change Password'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Tab
// ─────────────────────────────────────────────────────────────────────────────

class _DataTab extends StatefulWidget {
  const _DataTab();

  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  final _supabaseService = SupabaseService();
  final _apiService = ApiService();
  late Future<List<Map<String, dynamic>>> _categoriesFuture;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _categoriesFuture = _supabaseService.getCategories();
    });
  }

  List<Map<String, dynamic>> _userFields(List<Map<String, dynamic>> fields) {
    const systemCols = {'id', 'user_id', 'created_at', 'updated_at'};
    return fields
        .where((f) => !systemCols.contains(f['field_name'] as String? ?? ''))
        .toList();
  }

  // ── Per-row export (single category as CSV) ──
  Future<void> _exportCategory(Map<String, dynamic> category) async {
    final tableName = category['table_name'] as String;
    final displayName = category['display_name'] as String? ?? tableName;
    try {
      final fields = await _supabaseService.getFieldDefinitions(tableName);
      final items = await _supabaseService.getItems(tableName);
      final userFields = _userFields(fields);
      final headers =
          userFields.map((f) => f['display_name'] ?? f['field_name']).join(',');
      final rows = items.map((item) {
        return userFields.map((f) {
          final val = item[f['field_name']]?.toString() ?? '';
          if (val.contains(',') || val.contains('"') || val.contains('\n')) {
            return '"${val.replaceAll('"', '""')}"';
          }
          return val;
        }).join(',');
      }).join('\n');
      await Share.share('$headers\n$rows', subject: '$displayName Export');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export error: $e')));
      }
    }
  }

  // ── Export All categories as xlsx ──
  Future<void> _exportAll(List<Map<String, dynamic>> categories) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final excel = Excel.createExcel();
      // Remove the default sheet
      for (final s in excel.tables.keys.toList()) {
        excel.delete(s);
      }

      for (final category in categories) {
        final tableName = category['table_name'] as String;
        final displayName =
            (category['display_name'] as String? ?? tableName)
                .replaceAll(RegExp(r'[\\/*?:\[\]]'), '_');

        final fields = await _supabaseService.getFieldDefinitions(tableName);
        final items = await _supabaseService.getItems(tableName);
        final userFields = _userFields(fields);

        final sheet = excel[displayName];
        // Header row
        sheet.appendRow(
          userFields
              .map((f) =>
                  TextCellValue(f['display_name'] as String? ?? f['field_name'] as String? ?? ''))
              .toList(),
        );
        // Data rows
        for (final item in items) {
          sheet.appendRow(
            userFields.map((f) {
              final val = item[f['field_name']];
              return TextCellValue(val?.toString() ?? '');
            }).toList(),
          );
        }
      }

      final encoded = excel.encode();
      if (encoded == null) throw Exception('Failed to encode file');

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/stockai_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await File(path).writeAsBytes(encoded);
      await Share.shareXFiles(
        [XFile(path)],
        subject: 'StockAI Export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export error: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── Import from xlsx or csv ──
  Future<void> _importFile(List<Map<String, dynamic>> categories) async {
    if (_processing) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() => _processing = true);
    try {
      final ext = (file.extension ?? '').toLowerCase();
      if (ext == 'xlsx') {
        await _importXlsx(categories, bytes);
      } else {
        await _importCsv(categories, bytes);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _importXlsx(
      List<Map<String, dynamic>> categories, Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    int totalImported = 0;

    for (final sheetName in excel.tables.keys) {
      final table = excel.tables[sheetName];
      if (table == null || table.rows.isEmpty) continue;

      final category = categories.cast<Map<String, dynamic>?>().firstWhere(
            (c) =>
                (c!['display_name'] as String? ?? c['table_name'] as String)
                    .toLowerCase() ==
                sheetName.toLowerCase(),
            orElse: () => null,
          );
      if (category == null) continue;

      final tableName = category['table_name'] as String;
      final fields = await _supabaseService.getFieldDefinitions(tableName);
      final userFields = _userFields(fields);

      final headerRow = table.rows[0];
      final headers =
          headerRow.map((cell) => _cellToString(cell?.value).toLowerCase()).toList();

      final colToField = <int, String>{};
      for (int i = 0; i < headers.length; i++) {
        for (final f in userFields) {
          final dn = (f['display_name'] as String? ?? '').toLowerCase();
          final fn = (f['field_name'] as String? ?? '').toLowerCase();
          if (headers[i] == dn || headers[i] == fn) {
            colToField[i] = f['field_name'] as String;
            break;
          }
        }
      }

      for (int r = 1; r < table.rows.length; r++) {
        final row = table.rows[r];
        final rowData = <String, dynamic>{};
        for (final entry in colToField.entries) {
          if (entry.key < row.length) {
            rowData[entry.value] = _cellToString(row[entry.key]?.value);
          }
        }
        if (rowData.isNotEmpty) {
          await _supabaseService.upsertItem(tableName, rowData);
          totalImported++;
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $totalImported items')),
      );
    }
  }

  Future<void> _importCsv(
      List<Map<String, dynamic>> categories, Uint8List bytes) async {
    if (categories.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No categories to import into')),
        );
      }
      return;
    }

    final category = await _showSelectCategoryDialog(categories);
    if (category == null) return;

    final content = utf8.decode(bytes);
    final lines = content
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('CSV must have a header and at least one row')),
        );
      }
      return;
    }

    final tableName = category['table_name'] as String;
    final displayName = category['display_name'] as String? ?? tableName;

    try {
      final fields = await _supabaseService.getFieldDefinitions(tableName);
      final userFields = _userFields(fields);
      final headers = _parseCsvRow(lines[0]);

      final colToField = <int, String>{};
      for (int i = 0; i < headers.length; i++) {
        final header = headers[i].toLowerCase();
        for (final f in userFields) {
          final dn = (f['display_name'] as String? ?? '').toLowerCase();
          final fn = (f['field_name'] as String? ?? '').toLowerCase();
          if (header == dn || header == fn) {
            colToField[i] = f['field_name'] as String;
            break;
          }
        }
      }

      int imported = 0;
      for (int r = 1; r < lines.length; r++) {
        final values = _parseCsvRow(lines[r]);
        final rowData = <String, dynamic>{};
        for (final entry in colToField.entries) {
          if (entry.key < values.length) {
            rowData[entry.value] = values[entry.key];
          }
        }
        if (rowData.isNotEmpty) {
          await _supabaseService.upsertItem(tableName, rowData);
          imported++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $imported items into $displayName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import error: $e')));
      }
    }
  }

  Future<Map<String, dynamic>?> _showSelectCategoryDialog(
      List<Map<String, dynamic>> categories) async {
    Map<String, dynamic>? selected = categories.first;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Select Category'),
          content: DropdownButton<Map<String, dynamic>>(
            value: selected,
            isExpanded: true,
            items: categories.map((cat) {
              final name = cat['display_name'] as String? ??
                  cat['table_name'] as String;
              return DropdownMenuItem(value: cat, child: Text(name));
            }).toList(),
            onChanged: (val) => setDialogState(() => selected = val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected != null
                  ? () => Navigator.pop(ctx, selected)
                  : null,
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    final name =
        category['display_name'] as String? ?? category['table_name'] as String;
    final tableName = category['table_name'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Delete "$name" and all its items? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _apiService.deleteCategory(tableName);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showNewCategorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DataCategorySheet(
        onCreated: (name, icon) async {
          final emoji = icon.isNotEmpty ? '$icon ' : '';
          await _apiService
              .sendMessage('Create a new inventory category called "$emoji$name"');
          _reload();
        },
      ),
    );
  }

  List<String> _parseCsvRow(String row) {
    final result = <String>[];
    final current = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < row.length; i++) {
      final ch = row[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < row.length && row[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString());
    return result;
  }

  String _cellToString(CellValue? value) {
    if (value == null) return '';
    // In excel 4.x, TextCellValue.value is a TextSpan (rich text support)
    if (value is TextCellValue) return value.value.text ?? '';
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is BoolCellValue) return value.value.toString();
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final categories = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Section 1: Categories Management ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Categories',
                    style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                  onPressed: _showNewCategorySheet,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Create and manage your inventory categories.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (categories.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No categories yet.')),
              )
            else
              ...categories.map((category) {
                final icon = category['icon'] as String? ?? '📦';
                final name = category['display_name'] as String? ??
                    category['table_name'] as String;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Text(icon, style: const TextStyle(fontSize: 24)),
                    title: Text(name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.file_download_outlined),
                          tooltip: 'Export',
                          onPressed: () => _exportCategory(category),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error),
                          tooltip: 'Delete',
                          onPressed: () => _deleteCategory(category),
                        ),
                      ],
                    ),
                  ),
                );
              }),

            // ── Section 2: Import & Export ──
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text('Import & Export',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Export all categories as a single Excel file, or import from CSV / Excel.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: _processing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.file_download_outlined),
                    label: const Text('Export All'),
                    onPressed: _processing || categories.isEmpty
                        ? null
                        : () => _exportAll(categories),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import'),
                    onPressed: _processing
                        ? null
                        : () => _importFile(categories),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Accepts .xlsx (Excel / Google Sheets export) and .csv files.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New Category Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DataCategorySheet extends StatefulWidget {
  final Future<void> Function(String name, String icon) onCreated;
  const _DataCategorySheet({required this.onCreated});

  @override
  State<_DataCategorySheet> createState() => _DataCategorySheetState();
}

class _DataCategorySheetState extends State<_DataCategorySheet> {
  final _nameController = TextEditingController();
  String _selectedEmoji = '📦';
  bool _creating = false;

  static const _emojis = [
    '📦', '🖨️', '💻', '📱', '🖥️', '⌨️', '🖱️', '📷',
    '🎧', '🔌', '🔦', '🔧', '🔨', '📋', '📁', '🗄️',
    '🧰', '🔬', '📏', '✏️', '🏷️', '🛒', '🧪', '🔩',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    try {
      await widget.onCreated(name, _selectedEmoji);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New Category', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category),
            ),
            textInputAction: TextInputAction.done,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          Text('Icon', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _emojis.map((emoji) {
              final selected = emoji == _selectedEmoji;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _selectedEmoji = emoji),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Create Category'),
          ),
        ],
      ),
    );
  }
}
