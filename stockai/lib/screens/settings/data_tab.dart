part of '../settings_screen.dart';

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
          await _apiService.createCategory(name, icon);
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
