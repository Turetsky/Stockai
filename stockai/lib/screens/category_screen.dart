import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/supabase_service.dart';
import '../services/api_service.dart';

part 'category/manage_category_sheet.dart';
part 'category/item_form.dart';

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
    _dataFuture = _loadData();
  }

  void _reload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _dataFuture = _loadData(); });
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
        .toList()
      ..sort((a, b) => ((a['sort_order'] as num?) ?? 0)
          .compareTo((b['sort_order'] as num?) ?? 0));
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

  // Build item card matching the HTML preview format:
  //   ITEM NAME label → large bold identity value
  //   Uppercase secondary descriptor (extra fields)
  //   Divider footer → quantity badge left, extra field right
  Widget _buildItemCard(
      BuildContext context, Map<String, dynamic> item, List<Map<String, dynamic>> fields) {
    final theme = Theme.of(context);
    final userFields = _userFields(fields);
    if (userFields.isEmpty) return const SizedBox.shrink();

    // Identity (field[0]) → large title
    final identityKey = userFields[0]['field_name'] as String;
    final identityVal = item[identityKey]?.toString() ?? '';

    // Count (field[1]) → quantity badge
    final hasCount = userFields.length > 1;
    final countKey = hasCount ? userFields[1]['field_name'] as String : null;
    final countVal = countKey != null ? item[countKey]?.toString() ?? '' : '';

    // Extra fields (field[2+]) with non-empty values
    final extras = userFields.skip(2).where((f) {
      return (item[f['field_name']]?.toString() ?? '').isNotEmpty;
    }).toList();

    // First extra → shown as secondary desc (uppercase under title)
    final secVal = extras.isNotEmpty
        ? item[extras[0]['field_name']]?.toString() ?? ''
        : '';

    // Second extra → right side of footer
    final rightField = extras.length > 1 ? extras[1] : null;
    final rightLabel = rightField != null
        ? (rightField['display_name'] as String? ?? rightField['field_name'] as String).toUpperCase()
        : '';
    final rightVal = rightField != null
        ? item[rightField['field_name']]?.toString() ?? ''
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "ITEM NAME" micro-label
          Text(
            'ITEM NAME',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
            ),
          ),
          const SizedBox(height: 2),
          // Large bold identity value
          Text(
            identityVal.isNotEmpty ? identityVal : 'Item',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          // Secondary desc: first extra field, uppercase spaced
          if (secVal.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              secVal.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          // Footer
          if (hasCount || rightField != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.6)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Quantity badge
                if (hasCount && countVal.isNotEmpty) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QTY',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.9,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$countVal units',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                // Right-side extra field
                if (rightField != null && rightVal.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        rightLabel,
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.9,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        rightVal,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showItemSheet(
    List<Map<String, dynamic>> fields, {
    Map<String, dynamic>? existing,
  }) async {
    final userFields = _userFields(fields);

    final goManage = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: _ItemForm(
          fields: userFields,
          existing: existing,
          isEdit: existing != null,
          onSave: (data) async {
            if (existing != null) data['id'] = existing['id'];
            await _supabaseService.upsertItem(_tableName, data);
          },
          onManageFields: () => Navigator.pop(ctx, true),
        ),
      ),
    );

    // Sheet is fully closed — safe to reload now
    if (mounted && goManage != true) _reload();

    if (goManage == true) {
      await _showManageSheet(fields);
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
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: _ManageCategorySheet(
          category: widget.category,
          fields: _userFields(fields),
        ),
      ),
    );
    if (mounted) _reload();
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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showItemSheet(data.fields, existing: item),
                    child: _buildItemCard(context, item, data.fields),
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
