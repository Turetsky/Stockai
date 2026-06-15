part of '../category_screen.dart';

// ─────────────────────────────────────────────────────────────
//  Manage Category Sheet  (clean, settings-style)
// ─────────────────────────────────────────────────────────────

class _ManageCategorySheet extends StatefulWidget {
  final Map<String, dynamic> category;
  final List<Map<String, dynamic>> fields;

  const _ManageCategorySheet({
    required this.category,
    required this.fields,
  });

  @override
  State<_ManageCategorySheet> createState() => _ManageCategorySheetState();
}

class _ManageCategorySheetState extends State<_ManageCategorySheet> {
  final _supabaseService = SupabaseService();
  final _apiService = ApiService();
  late List<Map<String, dynamic>> _fields;
  String? _busyField;
  bool _busyCategory = false;
  bool _editingCategory = false;
  late TextEditingController _categoryController;

  String get _tableName => widget.category['table_name'] as String;
  String get _displayName =>
      widget.category['display_name'] as String? ?? _tableName;

  @override
  void initState() {
    super.initState();
    _fields = List.from(widget.fields)
      ..sort((a, b) => ((a['sort_order'] as num?) ?? 0)
          .compareTo((b['sort_order'] as num?) ?? 0));
    _categoryController =
        TextEditingController(text: widget.category['display_name'] ?? _tableName);
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _saveCategoryRename() async {
    final newName = _categoryController.text.trim();
    if (newName.isEmpty || newName == _displayName) {
      setState(() => _editingCategory = false);
      return;
    }
    setState(() { _editingCategory = false; _busyCategory = true; });
    try {
      await _supabaseService.renameCategory(_tableName, newName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        _categoryController.text = _displayName;
      }
    } finally {
      if (mounted) setState(() => _busyCategory = false);
    }
  }

  Future<void> _doFieldRename(
      String fieldName, String newDisplayName, String? newType) async {
    final idx = _fields.indexWhere((f) => f['field_name'] == fieldName);
    final current = idx >= 0
        ? (_fields[idx]['display_name'] as String? ?? fieldName)
        : fieldName;

    if ((newDisplayName.isEmpty || newDisplayName == current) &&
        newType == null) { return; }

    setState(() => _busyField = fieldName);
    final resolved = newDisplayName.isEmpty ? current : newDisplayName;
    try {
      if (newType != null) {
        await _apiService.updateField(_tableName, fieldName, resolved,
            newFieldType: newType);
      } else {
        await _supabaseService.renameFieldDisplay(_tableName, fieldName, resolved);
      }
      if (mounted) {
        setState(() {
          if (idx >= 0) {
            _fields[idx] = {
              ..._fields[idx],
              'display_name': resolved,
              if (newType != null) 'field_type': newType,
            };
          }
          _busyField = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busyField = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showRenameDialog(Map<String, dynamic> field,
      {bool isAnchor = false}) async {
    final fn = field['field_name'] as String;
    final dn = field['display_name'] as String? ?? fn;
    final ft = field['field_type'] as String? ?? 'text';
    final nameCtrl = TextEditingController(text: dn);
    String selectedType = ft;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Edit Field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
              ),
              if (!isAnchor) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Text')),
                    DropdownMenuItem(value: 'number', child: Text('Number')),
                    DropdownMenuItem(value: 'date', child: Text('Date')),
                    DropdownMenuItem(
                        value: 'textarea', child: Text('Long Text')),
                  ],
                  onChanged: (val) => setDlg(() => selectedType = val!),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(
                  ctx, {'name': nameCtrl.text.trim(), 'type': selectedType}),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    if (result == null) return;
    // Wait for the dialog exit animation to fully finish before updating state.
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _doFieldRename(
        fn, result['name']!, isAnchor ? null : result['type']);
  }

  Future<void> _deleteField(Map<String, dynamic> field) async {
    final fieldName = field['field_name'] as String;
    final displayName = field['display_name'] as String? ?? fieldName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Field'),
        content: Text(
            'Remove "$displayName" and all its data? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    setState(() => _busyField = fieldName);
    try {
      await _apiService.removeField(_tableName, fieldName);
      if (mounted) {
        setState(() =>
            _fields.removeWhere((f) => f['field_name'] == fieldName));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyField = null);
    }
  }

  Future<void> _addField() async {
    String selectedType = 'text';
    final nameController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add Field'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Field Name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('Text')),
                  DropdownMenuItem(value: 'number', child: Text('Number')),
                  DropdownMenuItem(value: 'date', child: Text('Date')),
                  DropdownMenuItem(
                      value: 'textarea', child: Text('Long Text')),
                ],
                onChanged: (val) => setDlg(() => selectedType = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx, {'name': name, 'type': selectedType});
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null) return;
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    final displayName = result['name']!;
    final fieldType = result['type']!;
    final fieldName = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');

    setState(() => _busyField = '__adding__');
    try {
      await _apiService.addField(_tableName, fieldName, displayName, fieldType);
      if (mounted) {
        setState(() => _fields.add({
          'field_name': fieldName,
          'display_name': displayName,
          'field_type': fieldType,
        }));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyField = null);
    }
  }

  Widget _buildSectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildRequiredFieldTile(
      BuildContext context, Map<String, dynamic> field, bool showDivider,
      {required int index}) {
    final theme = Theme.of(context);
    final fn = field['field_name'] as String;
    final isBusy = _busyField == fn;
    final roleLabel = index == 0 ? 'Item Name' : 'Quantity';
    final dn = field['display_name'] as String? ?? field['field_name'] as String;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          title: Row(
            children: [
              Expanded(
                child: Text(dn, style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  roleLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          trailing: isBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: theme.colorScheme.outline),
                  tooltip: 'Rename',
                  onPressed: () => _showRenameDialog(field, isAnchor: true),
                ),
        ),
        if (showDivider)
          Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ],
    );
  }

  Widget _buildCustomFieldTile(
      BuildContext context, Map<String, dynamic> field, bool showDivider) {
    final theme = Theme.of(context);
    final fn = field['field_name'] as String;
    final dn = field['display_name'] as String? ?? fn;
    final ft = field['field_type'] as String? ?? 'text';
    final isBusy = _busyField == fn;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          title: Text(dn, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(
            ft,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
          ),
          trailing: isBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit_outlined,
                          size: 18, color: theme.colorScheme.outline),
                      tooltip: 'Edit',
                      onPressed: () => _showRenameDialog(field),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: theme.colorScheme.error),
                      tooltip: 'Remove',
                      onPressed: () => _deleteField(field),
                    ),
                  ],
                ),
        ),
        if (showDivider)
          Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anchorFields = _fields.take(2).toList();
    final customFields = _fields.skip(2).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Category name ──
                Row(
                  children: [
                    Expanded(
                      child: _editingCategory
                          ? TextField(
                              controller: _categoryController,
                              autofocus: true,
                              style: theme.textTheme.titleLarge,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: UnderlineInputBorder(),
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _saveCategoryRename(),
                            )
                          : GestureDetector(
                              onTap: () =>
                                  setState(() => _editingCategory = true),
                              child: Text(
                                _categoryController.text.isNotEmpty
                                    ? _categoryController.text
                                    : _displayName,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                    ),
                    if (_busyCategory)
                      const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else if (_editingCategory) ...[
                      IconButton(
                        icon: const Icon(Icons.check, size: 20),
                        onPressed: _saveCategoryRename,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          _categoryController.text = _displayName;
                          setState(() => _editingCategory = false);
                        },
                      ),
                    ] else
                      IconButton(
                        icon: Icon(Icons.edit_outlined,
                            size: 18, color: theme.colorScheme.outline),
                        tooltip: 'Rename category',
                        onPressed: () =>
                            setState(() => _editingCategory = true),
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Required Fields ──
                if (anchorFields.isNotEmpty) ...[
                  _buildSectionLabel(context, 'Required Fields'),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: anchorFields
                          .asMap()
                          .entries
                          .map((e) => _buildRequiredFieldTile(
                              context,
                              e.value,
                              e.key < anchorFields.length - 1,
                              index: e.key))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Custom Fields ──
                _buildSectionLabel(context, 'Custom Fields'),
                if (customFields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No custom fields yet.',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: customFields
                          .asMap()
                          .entries
                          .map((e) => _buildCustomFieldTile(
                              context,
                              e.value,
                              e.key < customFields.length - 1))
                          .toList(),
                    ),
                  ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _busyField == '__adding__' ? null : _addField,
                  icon: _busyField == '__adding__'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                  label: const Text('Add Field'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
