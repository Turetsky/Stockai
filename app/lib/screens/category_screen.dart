import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/supabase_service.dart';
import '../services/api_service.dart';

class CategoryScreen extends StatefulWidget {
  final Map<String, dynamic> category;

  const CategoryScreen({super.key, required this.category});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final _supabaseService = SupabaseService();
  late Future<_CategoryData> _dataFuture;

  String get _tableName => widget.category['table_name'] as String;
  String get _displayName =>
      widget.category['display_name'] as String? ?? _tableName;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<_CategoryData> _loadData() async {
    final fields = await _supabaseService.getFieldDefinitions(_tableName);
    final items = await _supabaseService.getItems(_tableName);
    return _CategoryData(fields: fields, items: items);
  }

  List<Map<String, dynamic>> _userFields(List<Map<String, dynamic>> fields) {
    const systemCols = {'id', 'user_id', 'created_at', 'updated_at'};
    return fields
        .where((f) => !systemCols.contains(f['field_name'] as String? ?? ''))
        .toList();
  }

  // Field 1 (index 0) is always the item title.
  String _itemTitle(
      Map<String, dynamic> item, List<Map<String, dynamic>> fields) {
    final userFields = _userFields(fields);
    if (userFields.isEmpty) return item['id']?.toString() ?? 'Item';
    final titleField = userFields.first;
    final key = titleField['field_name'] as String? ?? '';
    final val = item[key]?.toString() ?? '';
    return val.isNotEmpty ? val : 'Item';
  }

  // Show remaining fields (skip title) as a subtitle.
  String _itemSummary(
      Map<String, dynamic> item, List<Map<String, dynamic>> fields) {
    final userFields = _userFields(fields);
    if (userFields.length <= 1) return '';
    final parts = userFields
        .skip(1)
        .take(3)
        .map((f) {
          final name = f['field_name'] as String? ?? '';
          final val = item[name];
          if (val == null || val.toString().isEmpty) return null;
          return val.toString();
        })
        .whereType<String>()
        .toList();
    return parts.join(' · ');
  }

  Future<void> _showItemSheet(
    List<Map<String, dynamic>> fields, {
    Map<String, dynamic>? existing,
  }) async {
    final userFields = _userFields(fields);
    final controllers = <String, TextEditingController>{
      for (final f in userFields)
        f['field_name'] as String: TextEditingController(
          text: existing?[f['field_name']]?.toString() ?? '',
        ),
    };

    final goManage = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ItemForm(
        fields: userFields,
        controllers: controllers,
        isEdit: existing != null,
        onSave: (data) async {
          if (existing != null) data['id'] = existing['id'];
          await _supabaseService.upsertItem(_tableName, data);
          if (mounted) _reload();
        },
        onManageFields: () => Navigator.pop(ctx, true),
      ),
    );

    for (final c in controllers.values) {
      c.dispose();
    }

    if (goManage == true) {
      await _showManageSheet(fields);
      _reload();
    }
  }

  Future<void> _showManageSheet(List<Map<String, dynamic>> fields) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ManageCategorySheet(
        category: widget.category,
        fields: _userFields(fields),
        onChanged: _reload,
      ),
    );
  }

  Future<void> _exportCsv(
      List<Map<String, dynamic>> fields, List<Map<String, dynamic>> items) async {
    final userFields = _userFields(fields);
    final headers = userFields.map((f) => f['display_name'] ?? f['field_name']).join(',');
    final rows = items.map((item) {
      return userFields
          .map((f) {
            final val = item[f['field_name']]?.toString() ?? '';
            if (val.contains(',') || val.contains('"') || val.contains('\n')) {
              return '"${val.replaceAll('"', '""')}"';
            }
            return val;
          })
          .join(',');
    }).join('\n');

    final csv = '$headers\n$rows';
    await Share.share(csv, subject: '$_displayName Export');
  }

  Future<void> _importCsv(List<Map<String, dynamic>> fields) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) return;

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
              content: Text(
                  'CSV must have a header row and at least one data row.')),
        );
      }
      return;
    }

    final headers = _parseCsvRow(lines[0]);
    final userFields = _userFields(fields);

    final colToField = <int, String>{};
    for (int i = 0; i < headers.length; i++) {
      final header = headers[i].toLowerCase();
      for (final f in userFields) {
        final displayName = (f['display_name'] as String? ?? '').toLowerCase();
        final fieldName = (f['field_name'] as String? ?? '').toLowerCase();
        if (header == displayName || header == fieldName) {
          colToField[i] = f['field_name'] as String;
          break;
        }
      }
    }

    int imported = 0;
    try {
      for (int r = 1; r < lines.length; r++) {
        final values = _parseCsvRow(lines[r]);
        final rowData = <String, dynamic>{};
        for (final entry in colToField.entries) {
          if (entry.key < values.length) {
            rowData[entry.value] = values[entry.key];
          }
        }
        if (rowData.isNotEmpty) {
          await _supabaseService.upsertItem(_tableName, rowData);
          imported++;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import error: $e')),
        );
      }
      return;
    }

    _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $imported items')),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
        actions: [
          FutureBuilder<_CategoryData>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.tune),
                    tooltip: 'Manage Category',
                    onPressed: () => _showManageSheet(snapshot.data!.fields),
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload),
                    tooltip: 'Import CSV',
                    onPressed: () => _importCsv(snapshot.data!.fields),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Export CSV',
                    onPressed: () => _exportCsv(
                      snapshot.data!.fields,
                      snapshot.data!.items,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<_CategoryData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading items: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final items = data.items;

          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    'No items yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add your first item',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final item = items[index];
              final title = _itemTitle(item, data.fields);
              final subtitle = _itemSummary(item, data.fields);

              final itemId = item['id'].toString();
              return Dismissible(
                key: ValueKey(itemId),
                background: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: const Icon(Icons.edit_outlined, color: Colors.white),
                ),
                secondaryBackground: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    return await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Item'),
                        content: Text('Delete "$title"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.error),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  } else {
                    _showItemSheet(data.fields, existing: item);
                    return false;
                  }
                },
                onDismissed: (_) async {
                  await _supabaseService.deleteItem(_tableName, itemId);
                  _reload();
                },
                child: Card(
                  child: ListTile(
                    title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                    onTap: () => _showItemSheet(data.fields, existing: item),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FutureBuilder<_CategoryData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          return FloatingActionButton(
            onPressed: snapshot.hasData
                ? () => _showItemSheet(snapshot.data!.fields)
                : null,
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }
}

class _CategoryData {
  final List<Map<String, dynamic>> fields;
  final List<Map<String, dynamic>> items;
  const _CategoryData({required this.fields, required this.items});
}

// ─────────────────────────────────────────────────────────────
//  Manage Category Sheet  (clean, settings-style)
// ─────────────────────────────────────────────────────────────

class _ManageCategorySheet extends StatefulWidget {
  final Map<String, dynamic> category;
  final List<Map<String, dynamic>> fields;
  final VoidCallback onChanged;

  const _ManageCategorySheet({
    required this.category,
    required this.fields,
    required this.onChanged,
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
    _fields = List.from(widget.fields);
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
      widget.onChanged();
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
      widget.onChanged();
      if (mounted && idx >= 0) {
        setState(() => _fields[idx] = {
          ..._fields[idx],
          'display_name': resolved,
          if (newType != null) 'field_type': newType,
        });
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

    setState(() => _busyField = fieldName);
    try {
      await _apiService.removeField(_tableName, fieldName);
      widget.onChanged();
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
                onPressed: () {
                  nameController.dispose();
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                nameController.dispose();
                if (name.isEmpty) return;
                Navigator.pop(ctx, {'name': name, 'type': selectedType});
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
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
      widget.onChanged();
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
                  'Required',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Text(
            ft,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
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
        Flexible(
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
                              e.key < anchorFields.length - 1))
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

// ─────────────────────────────────────────────────────────────
//  Item Form  (add / edit item)
// ─────────────────────────────────────────────────────────────

class _ItemForm extends StatefulWidget {
  final List<Map<String, dynamic>> fields;
  final Map<String, TextEditingController> controllers;
  final bool isEdit;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final VoidCallback? onManageFields;

  const _ItemForm({
    required this.fields,
    required this.controllers,
    required this.isEdit,
    required this.onSave,
    this.onManageFields,
  });

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  bool _saving = false;

  Future<void> _submit() async {
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        for (final f in widget.fields)
          f['field_name'] as String:
              widget.controllers[f['field_name']]?.text.trim() ?? '',
      };
      await widget.onSave(data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.isEdit ? 'Edit Item' : 'Add Item',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (widget.onManageFields != null)
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: 'Manage Fields',
                  onPressed: widget.onManageFields,
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...widget.fields.asMap().entries.map((entry) {
            final idx = entry.key;
            final f = entry.value;
            final fieldName = f['field_name'] as String;
            final displayName = f['display_name'] as String? ?? fieldName;
            final fieldType = f['field_type'] as String? ?? 'text';
            final isAnchor = idx < 2;
            final isNumber = fieldType == 'number' ||
                fieldType == 'integer' ||
                fieldType == 'float';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: widget.controllers[fieldName],
                keyboardType: isNumber
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                maxLines: fieldType == 'textarea' ? 3 : 1,
                decoration: InputDecoration(
                  labelText: isAnchor ? '$displayName *' : displayName,
                  border: const OutlineInputBorder(),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(widget.isEdit ? 'Save Changes' : 'Add Item'),
          ),
        ],
      ),
    );
  }
}
