part of '../settings_screen.dart';

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
  // Curated shortlist (ai, API-verified premade + free-tier safe). Eric is the
  // default per QA "voice too generic".
  static const _voices = [
    {'id': 'cjVigY5qzO86Huf0OWal', 'name': 'Eric — Smooth & Trustworthy'},
    {'id': 'cgSgspJ2msm6clMCkdW9', 'name': 'Jessica — Playful & Bright'},
    {'id': 'JBFqnCBsd6RMkjVDRZzb', 'name': 'George — British Storyteller'},
    {'id': 'nPczCjzI2devNBz1zQrb', 'name': 'Brian — Deep & Resonant'},
    {'id': 'IKne3meq5aSn9XLyUdCD', 'name': 'Charlie — Confident & Energetic'},
    {'id': 'N2lVS1w4EtoT3dr4eOWO', 'name': 'Callum — Husky & Mischievous'},
    {'id': 'SAz9YHcvj6GT2YYXdXww', 'name': 'River — Relaxed & Neutral'},
  ];

  final _supabaseService = SupabaseService();
  String _selectedVoiceId = 'cjVigY5qzO86Huf0OWal'; // Eric — premade, free tier
  double _stability = 0.4;
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
      // Only honor a saved voice if it's still in the curated shortlist —
      // otherwise the Dropdown would assert (no matching item). A previously
      // saved voice that was dropped (e.g. Sarah) falls back to the default.
      if (v != null && v.isNotEmpty && _voices.any((e) => e['id'] == v)) {
        _selectedVoiceId = v;
      }
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
