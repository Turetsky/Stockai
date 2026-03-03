import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/supabase_service.dart';

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

  String _itemSummary(
      Map<String, dynamic> item, List<Map<String, dynamic>> fields) {
    final userFields = _userFields(fields);
    if (userFields.isEmpty) return item['id']?.toString() ?? '';
    final parts = userFields.take(3).map((f) {
      final name = f['field_name'] as String? ?? '';
      final val = item[name];
      if (val == null || val.toString().isEmpty) return null;
      return val.toString();
    }).whereType<String>().toList();
    return parts.join(' · ');
  }

  String _itemTitle(
      Map<String, dynamic> item, List<Map<String, dynamic>> fields) {
    final userFields = _userFields(fields);
    if (userFields.isEmpty) return item['id']?.toString() ?? 'Item';
    final firstField = userFields.first['field_name'] as String? ?? '';
    return item[firstField]?.toString() ?? 'Item';
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

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
      ),
    );

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Future<void> _deleteItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _supabaseService.deleteItem(_tableName, id);
      _reload();
    }
  }

  Future<void> _exportCsv(
      List<Map<String, dynamic>> fields, List<Map<String, dynamic>> items) async {
    final userFields = _userFields(fields);
    final headers = userFields.map((f) => f['display_name'] ?? f['field_name']).join(',');
    final rows = items.map((item) {
      return userFields
          .map((f) {
            final val = item[f['field_name']]?.toString() ?? '';
            // Escape commas and quotes for CSV
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

    // Map CSV column index → field_name (case-insensitive match on display_name or field_name)
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

              return Card(
                child: ListTile(
                  title: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteItem(item['id'].toString()),
                  ),
                  onTap: () => _showItemSheet(data.fields, existing: item),
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

class _ItemForm extends StatefulWidget {
  final List<Map<String, dynamic>> fields;
  final Map<String, TextEditingController> controllers;
  final bool isEdit;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _ItemForm({
    required this.fields,
    required this.controllers,
    required this.isEdit,
    required this.onSave,
  });

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  bool _saving = false;

  Future<void> _submit() async {
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
          Text(
            widget.isEdit ? 'Edit Item' : 'Add Item',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ...widget.fields.map((f) {
            final fieldName = f['field_name'] as String;
            final displayName = f['display_name'] as String? ?? fieldName;
            final fieldType = f['field_type'] as String? ?? 'text';
            final isNumber =
                fieldType == 'number' || fieldType == 'integer' || fieldType == 'float';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: widget.controllers[fieldName],
                keyboardType: isNumber
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                maxLines: fieldType == 'textarea' ? 3 : 1,
                decoration: InputDecoration(
                  labelText: displayName,
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
