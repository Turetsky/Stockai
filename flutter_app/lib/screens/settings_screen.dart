import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/theme_settings.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabaseService = SupabaseService();
  final _nameController = TextEditingController();
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

  Future<void> _setThemeMode(ThemeMode mode) async {
    final current = themeNotifier.value;
    themeNotifier.value = current.copyWith(mode: mode);
    final modeStr = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    try {
      await _supabaseService.setUiSetting('theme_mode', modeStr);
    } catch (_) {}
  }

  Future<void> _setSeedColor(Color color) async {
    final current = themeNotifier.value;
    themeNotifier.value = current.copyWith(seedColor: color);
    final hex = '#${color.toARGB32().toRadixString(16).substring(2)}';
    try {
      await _supabaseService.setUiSetting('theme_color', hex);
    } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Appearance'),
            Tab(text: 'Profile'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AppearanceTab(
            onModeChanged: _setThemeMode,
            onColorChanged: _setSeedColor,
          ),
          _ProfileTab(
            nameController: _nameController,
            saving: _savingName,
            onSave: _saveName,
            onLogout: _logout,
          ),
        ],
      ),
    );
  }
}

class _AppearanceTab extends StatelessWidget {
  final Future<void> Function(ThemeMode) onModeChanged;
  final Future<void> Function(Color) onColorChanged;

  const _AppearanceTab({
    required this.onModeChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeSettings>(
      valueListenable: themeNotifier,
      builder: (context, settings, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Theme Mode', style: Theme.of(context).textTheme.titleMedium),
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
              onSelectionChanged: (s) => onModeChanged(s.first),
            ),
            const SizedBox(height: 24),
            Text('Color Theme', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.0,
              children: kThemePresets.map((preset) {
                final isSelected = settings.seedColor.toARGB32() == preset.seedColor.toARGB32();
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onColorChanged(preset.seedColor),
                  child: Container(
                    decoration: BoxDecoration(
                      color: preset.seedColor,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                      boxShadow: isSelected
                          ? [BoxShadow(color: preset.seedColor.withValues(alpha: 0.5), blurRadius: 8)]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isSelected)
                          const Icon(Icons.check, color: Colors.white, size: 16),
                        if (isSelected) const SizedBox(width: 4),
                        Text(
                          preset.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileTab extends StatelessWidget {
  final TextEditingController nameController;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onLogout;

  const _ProfileTab({
    required this.nameController,
    required this.saving,
    required this.onSave,
    required this.onLogout,
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save Name'),
        ),
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
              icon: Icon(_obscureNew ? Icons.visibility : Icons.visibility_off),
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
              icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Change Password'),
        ),
      ],
    );
  }
}
