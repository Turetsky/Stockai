part of '../chat_screen.dart';

// ---------- Manage Categories Bottom Sheet ----------

class _ManageCategoriesSheet extends StatefulWidget {
  final VoidCallback onCategoriesChanged;
  final VoidCallback onAddNew;

  const _ManageCategoriesSheet({
    required this.onCategoriesChanged,
    required this.onAddNew,
  });

  @override
  State<_ManageCategoriesSheet> createState() => _ManageCategoriesSheetState();
}

class _ManageCategoriesSheetState extends State<_ManageCategoriesSheet> {
  final _supabaseService = SupabaseService();
  final _apiService = ApiService();
  List<Map<String, dynamic>>? _categories;
  String? _error;
  String? _deletingTable;
  String? _renamingTable; // table currently showing inline rename field
  final Map<String, TextEditingController> _renameControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _renameControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cats = await _supabaseService.getCategories();
      if (mounted) setState(() => _categories = cats);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _saveRename(String tableName, String currentName) async {
    final controller = _renameControllers[tableName];
    if (controller == null) return;
    final newName = controller.text.trim();
    setState(() => _renamingTable = null);
    if (newName.isEmpty || newName == currentName) return;
    try {
      await _supabaseService.renameCategory(tableName, newName);
      widget.onCategoriesChanged();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteCategory(String tableName, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
            'Delete "$displayName" and all its items? This cannot be undone.'),
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
    if (confirmed != true) return;

    setState(() => _deletingTable = tableName);
    try {
      await _apiService.deleteCategory(tableName);
      widget.onCategoriesChanged();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingTable = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text('Manage Categories', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_error != null)
            Text('Error: $_error',
                style: TextStyle(color: theme.colorScheme.error))
          else if (_categories == null)
            const Center(child: CircularProgressIndicator())
          else if (_categories!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No categories yet.', textAlign: TextAlign.center),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _categories!.length,
                itemBuilder: (context, index) {
                  final cat = _categories![index];
                  final icon = cat['icon'] as String? ?? '';
                  final name = cat['display_name'] as String? ??
                      cat['table_name'] as String;
                  final tableName = cat['table_name'] as String;
                  final iconRunes = icon.runes.toList();
                  final isEmoji =
                      iconRunes.isNotEmpty && iconRunes.first > 0x2000;
                  // Strip leading emoji + whitespace from display_name (emoji shown in leading)
                  final displayName = isEmoji
                      ? name.replaceFirst(
                          RegExp(r'^\p{Emoji_Presentation}\s*', unicode: true), '')
                      : name;
                  final isDeleting = _deletingTable == tableName;
                  final isRenaming = _renamingTable == tableName;
                  if (isRenaming &&
                      !_renameControllers.containsKey(tableName)) {
                    _renameControllers[tableName] =
                        TextEditingController(text: displayName);
                  }
                  return ListTile(
                    leading: isEmoji
                        ? Text(icon, style: const TextStyle(fontSize: 22))
                        : const Icon(Icons.inventory_2_outlined),
                    title: isRenaming
                        ? TextField(
                            controller: _renameControllers[tableName],
                            autofocus: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) =>
                                _saveRename(tableName, name),
                          )
                        : GestureDetector(
                            onTap: () {
                              _renameControllers[tableName] =
                                  TextEditingController(text: displayName);
                              setState(() => _renamingTable = tableName);
                            },
                            child: Text(displayName),
                          ),
                    trailing: isDeleting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : isRenaming
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check, size: 18),
                                    onPressed: () =>
                                        _saveRename(tableName, name),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(
                                        () => _renamingTable = null),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon:
                                        const Icon(Icons.edit_outlined, size: 18),
                                    tooltip: 'Rename',
                                    onPressed: () {
                                      _renameControllers[tableName] =
                                          TextEditingController(text: name);
                                      setState(
                                          () => _renamingTable = tableName);
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        color: theme.colorScheme.error),
                                    tooltip: 'Delete',
                                    onPressed: () =>
                                        _deleteCategory(tableName, name),
                                  ),
                                ],
                              ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onAddNew();
            },
            icon: const Icon(Icons.add),
            label: const Text('New Category'),
          ),
        ],
      ),
    );
  }
}

// ---------- New Category Bottom Sheet ----------

class _NewCategorySheet extends StatefulWidget {
  final Future<void> Function(String name, String icon) onCreated;

  const _NewCategorySheet({required this.onCreated});

  @override
  State<_NewCategorySheet> createState() => _NewCategorySheetState();
}

class _NewCategorySheetState extends State<_NewCategorySheet> {
  final _nameController = TextEditingController();
  String _selectedEmoji = '📦';
  bool _creating = false;

  static const _emojis = [
    '📦', '🖨️', '💻', '📱', '🖥️', '⌨️', '🖱️', '📷',
    '🎧', '🔌', '🔦', '🔧', '🔨', '📋', '📁', '🗄️',
    '🧰', '🔬', '📏', '✏️', '🏷️', '🛒', '🧪', '🔩',
  ];

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    try {
      await widget.onCreated(name, _selectedEmoji);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
