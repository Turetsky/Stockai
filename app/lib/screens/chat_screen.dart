import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'category_screen.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _apiService = ApiService();
  final _supabaseService = SupabaseService();
  final List<ChatMessage> _messages = [];
  bool _sending = false;

  // Voice input
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  // Drawer state
  late Future<List<Map<String, dynamic>>> _categoriesFuture;
  Future<Map<String, String>>? _uiSettingsFuture;

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
      text:
          "Hi! I'm your inventory assistant. I can help you manage categories, add items, change themes, and more. What would you like to do?",
      isUser: false,
    ));
    _initSpeech();
    _initTts();
    _loadCategories();
    _uiSettingsFuture = _supabaseService.getUiSettings();
    loadThemeFromSupabase();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (_) { if (mounted) setState(() => _isListening = false); },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _tts.setStartHandler(() { if (mounted) setState(() => _isSpeaking = true); });
    _tts.setCompletionHandler(() { if (mounted) setState(() => _isSpeaking = false); });
    _tts.setCancelHandler(() { if (mounted) setState(() => _isSpeaking = false); });
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  void _loadCategories() {
    _categoriesFuture = _supabaseService.getCategories();
  }

  Future<void> _sendMessage({bool concise = false, bool speak = false}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    await _tts.stop();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _sending = true;
    });
    _messageController.clear();
    _scrollToBottom();

    // Build history from all messages except the just-added current user message
    final historyMessages = _messages
        .sublist(0, _messages.length - 1)
        .where((m) => !m.isError)
        .map<Map<String, String>>((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();

    try {
      final response = await _apiService.sendMessage(
        text,
        concise: concise,
        history: historyMessages,
      );
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(text: response, isUser: false));
        });
      }
      if (speak) {
        await _tts.speak(response);
      }
      // Reload theme + app name in case the AI changed them via set_ui_setting
      await loadThemeFromSupabase();
      if (mounted) {
        setState(() {
          _uiSettingsFuture = _supabaseService.getUiSettings();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
              ChatMessage(text: 'Error: ${e.toString()}', isUser: false, isError: true));
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    await _tts.stop();
    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          setState(() {
            _messageController.text = result.recognizedWords;
            _isListening = false;
          });
          if (result.recognizedWords.isNotEmpty) {
            _sendMessage(concise: true, speak: true);
          }
        } else {
          setState(() {
            _messageController.text = result.recognizedWords;
          });
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(cancelOnError: true),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _showManageCategoriesSheet() {
    Navigator.pop(context); // close drawer
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ManageCategoriesSheet(
        onCategoriesChanged: () => setState(() => _loadCategories()),
        onAddNew: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => _NewCategorySheet(
              onCreated: (name, icon) async {
                final msg = 'Create a new category called "$name" with the icon "$icon"';
                _messageController.text = msg;
                await _sendMessage();
                setState(() => _loadCategories());
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: FutureBuilder<Map<String, String>>(
        future: _uiSettingsFuture,
        builder: (context, uiSnapshot) {
          final uiSettings = uiSnapshot.data ?? {};
          final rawAppName = uiSettings['app_name'] ?? 'Inventory Manager';
          // Extract leading emoji (per sidebar.js pattern)
          String appLogo = '';
          String appName = rawAppName;
          final runes = rawAppName.runes.toList();
          if (runes.isNotEmpty && runes.first > 0x2000) {
            final emojiEnd = rawAppName.indexOf(' ');
            if (emojiEnd > 0) {
              appLogo = rawAppName.substring(0, emojiEnd);
              appName = rawAppName.substring(emojiEnd + 1);
            } else {
              appLogo = rawAppName;
              appName = '';
            }
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 24,
                  20,
                  20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Color.lerp(
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.tertiary,
                        0.35,
                      )!,
                    ],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (appLogo.isNotEmpty) ...[
                      Text(appLogo, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            appName.isNotEmpty ? appName : 'Inventory Manager',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            supabase.auth.currentUser?.email ?? '',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _categoriesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final categories = snapshot.data ?? [];
                    if (categories.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No categories yet.\nTap + to create one.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final icon = cat['icon'] as String? ?? '';
                        final name = cat['display_name'] as String? ??
                            cat['table_name'] as String;
                        final iconRunes = icon.runes.toList();
                        final isEmoji =
                            iconRunes.isNotEmpty && iconRunes.first > 0x2000;
                        return ListTile(
                          leading: isEmoji
                              ? Text(icon,
                                  style: const TextStyle(fontSize: 22))
                              : const Icon(Icons.inventory_2_outlined),
                          title: Text(name),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CategoryScreen(category: cat),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.category),
                title: const Text('Manage Categories'),
                onTap: _showManageCategoriesSheet,
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = supabase.auth.currentUser;
    final displayName =
        user?.userMetadata?['display_name'] ?? user?.email?.split('@')[0] ?? 'User';

    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: const Text('Inventory Manager'),
        centerTitle: true,
        elevation: 1,
        actions: [
          Theme(
            data: theme.copyWith(
              popupMenuTheme: PopupMenuThemeData(
                color: theme.colorScheme.surfaceContainerHigh,
                surfaceTintColor: Colors.transparent,
                textStyle: TextStyle(color: theme.colorScheme.onSurface),
              ),
            ),
            child: PopupMenuButton(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                displayName.toString().substring(0, 1).toUpperCase(),
                style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold),
              ),
            ),
            itemBuilder: (context) => <PopupMenuEntry>[
              PopupMenuItem(
                onTap: () {},
                child: Text(displayName.toString(),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
              ),
              PopupMenuItem(
                onTap: () {},
                child: Text(user?.email ?? '',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                onTap: _logout,
                child: const Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
          ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _sending) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Thinking...',
                            style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic)),
                      ],
                    ),
                  );
                }
                return _buildMessageBubble(_messages[index], theme);
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  if (_speechAvailable)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: _isListening
                          ? BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: IconButton(
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? theme.colorScheme.error : null,
                        ),
                        tooltip:
                            _isListening ? 'Stop listening' : 'Voice input',
                        onPressed: _toggleListening,
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening...'
                            : 'Ask me anything about your inventory...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.3),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      maxLines: 5,
                      minLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isSpeaking)
                    IconButton.filled(
                      onPressed: _stopSpeaking,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      icon: const Icon(Icons.stop_rounded),
                      tooltip: 'Stop speaking',
                    )
                  else
                    IconButton.filled(
                      onPressed: _sending ? null : _sendMessage,
                      icon: const Icon(Icons.send),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, ThemeData theme) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: msg.isError
              ? Colors.red.shade50
              : msg.isUser
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
          ),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.isError
                ? Colors.red.shade700
                : msg.isUser
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  ChatMessage({required this.text, required this.isUser, this.isError = false});
}

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
                  final isDeleting = _deletingTable == tableName;
                  final isRenaming = _renamingTable == tableName;
                  if (isRenaming &&
                      !_renameControllers.containsKey(tableName)) {
                    _renameControllers[tableName] =
                        TextEditingController(text: name);
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
                                  TextEditingController(text: name);
                              setState(() => _renamingTable = tableName);
                            },
                            child: Text(name),
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
