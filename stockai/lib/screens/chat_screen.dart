import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import '../main.dart';
import '../theme/app_style.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'category_screen.dart';
import 'settings_screen.dart';

part 'chat/category_sheets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  final _apiService = ApiService();
  final _supabaseService = SupabaseService();
  final List<ChatMessage> _messages = [];
  bool _sending = false;

  // Streaming state (used when ApiService.useStreaming is true)
  StreamSubscription<ChatEvent>? _streamSub;
  String? _streamingText; // live assistant text being built; null when idle
  String? _toolChip; // current "working…" hint label, null when none

  // Voice input
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  // TTS
  final AudioPlayer _player = AudioPlayer();
  bool _isSpeaking = false;
  // Default to a free-tier *premade* voice (Sarah). The old default (Rachel,
  // 21m00…) is a library voice → 402 on free plans. A user's saved tts_voice_id
  // still overrides this on load.
  String _ttsVoiceId = 'EXAVITQu4vr4xnSDxMaL'; // ElevenLabs Sarah (premade, free)
  double _ttsStability = 0.5;
  double _ttsSimilarityBoost = 0.75;
  bool _ttsWarned = false; // show a TTS-failure notice at most once per session

  // Drawer state
  late Future<List<Map<String, dynamic>>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
      text:
          "Hi! I'm your inventory assistant. I can help you manage categories, add items, change themes, and more. What would you like to do?",
      isUser: false,
    ));
    _initSpeech();
    _initPlayer();
    _loadCategories();
    loadThemeFromSupabase();
    // Auto-focus the chat input when the screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
    });
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

  void _initPlayer() {
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isSpeaking = state == PlayerState.playing);
    });
    // Load voice + TTS params
    _supabaseService.getUiSettings().then((settings) {
      if (!mounted) return;
      setState(() {
        final v = settings['tts_voice_id'];
        if (v != null && v.isNotEmpty) _ttsVoiceId = v;
        final stab = double.tryParse(settings['tts_stability'] ?? '');
        if (stab != null) _ttsStability = stab.clamp(0.0, 1.0);
        final sim = double.tryParse(settings['tts_similarity_boost'] ?? '');
        if (sim != null) _ttsSimilarityBoost = sim.clamp(0.0, 1.0);
      });
    });
  }

  Future<void> _stopSpeaking() async {
    await _player.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  void _loadCategories() {
    _categoriesFuture = _supabaseService.getCategories();
  }

  Future<void> _sendMessage({bool concise = false, bool speak = false}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    await _player.stop();
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

    if (ApiService.useStreaming) {
      await _streamReply(text, historyMessages, concise: concise, speak: speak);
    } else {
      await _sendNonStreaming(text, historyMessages,
          concise: concise, speak: speak);
    }
  }

  /// Original one-shot path: await the full reply, then add it as one bubble.
  Future<void> _sendNonStreaming(
    String text,
    List<Map<String, String>> history, {
    required bool concise,
    required bool speak,
  }) async {
    try {
      final response = await _apiService.sendMessage(
        text,
        concise: concise,
        history: history,
      );
      if (mounted) {
        setState(() => _messages.add(ChatMessage(text: response, isUser: false)));
      }
      await _afterReply(response, speak);
    } catch (e) {
      _handleSendError(e);
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  /// Streaming path: consume the SSE [ChatEvent] stream, building the assistant
  /// bubble live. Applies the contract's reset rule (clear bubble on a
  /// `turn` with stop_reason "tool_use") and shows a "working…" chip during
  /// tool calls so the reset is never visible as a flash of vanishing text.
  Future<void> _streamReply(
    String text,
    List<Map<String, String>> history, {
    required bool concise,
    required bool speak,
  }) async {
    final completer = Completer<void>();
    setState(() {
      _streamingText = '';
      _toolChip = null;
    });

    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    _streamSub = _apiService
        .streamMessage(text, concise: concise, history: history)
        .listen(
      (event) {
        if (!mounted) return;
        switch (event.type) {
          case ChatEventType.start:
            break;
          case ChatEventType.token:
            setState(() {
              _toolChip = null; // answer is flowing — drop any tool chip
              _streamingText = (_streamingText ?? '') + (event.text ?? '');
            });
            _maybeAutoScroll();
            break;
          case ChatEventType.turn:
            // Pre-tool "thinking" text isn't the answer — discard it. The real
            // answer is whatever streams after the last tool turn.
            if (event.stopReason == 'tool_use') {
              setState(() => _streamingText = '');
            }
            break;
          case ChatEventType.tool:
            if (event.toolStatus == 'running') {
              setState(() => _toolChip = _toolLabel(event.toolName));
            }
            break;
          case ChatEventType.done:
            final full = (event.message != null && event.message!.isNotEmpty)
                ? event.message!
                : (_streamingText ?? '');
            setState(() {
              if (full.trim().isNotEmpty) {
                _messages.add(ChatMessage(text: full, isUser: false));
              }
              _streamingText = null;
              _toolChip = null;
              _sending = false;
            });
            _scrollToBottom();
            _afterReply(full, speak); // fire-and-forget TTS + reload
            break;
          case ChatEventType.error:
            setState(() {
              _streamingText = null;
              _toolChip = null;
              _messages.add(ChatMessage(
                  text: 'Error: ${event.error}', isUser: false, isError: true));
              _sending = false;
            });
            _scrollToBottom();
            break;
        }
      },
      onError: (Object e) {
        _handleSendError(e);
        if (mounted) {
          setState(() {
            _streamingText = null;
            _toolChip = null;
            _sending = false;
          });
        }
        finish();
      },
      onDone: () {
        // Safety net: stream closed without an explicit done/error event.
        if (mounted && _sending) {
          setState(() {
            if ((_streamingText ?? '').trim().isNotEmpty) {
              _messages.add(ChatMessage(text: _streamingText!, isUser: false));
            }
            _streamingText = null;
            _toolChip = null;
            _sending = false;
          });
          _scrollToBottom();
        }
        _streamSub = null;
        finish();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  /// Stop an in-flight stream (stop button). Keeps whatever text arrived so far.
  Future<void> _stopStreaming() async {
    await _streamSub?.cancel();
    _streamSub = null;
    await _player.stop();
    if (mounted) {
      setState(() {
        if ((_streamingText ?? '').trim().isNotEmpty) {
          _messages.add(ChatMessage(text: _streamingText!, isUser: false));
        }
        _streamingText = null;
        _toolChip = null;
        _sending = false;
        _isSpeaking = false;
      });
    }
  }

  /// Post-reply work shared by both paths: speak the answer (if requested) and
  /// reload theme + categories in case the AI changed them.
  Future<void> _afterReply(String fullText, bool speak) async {
    if (speak && fullText.trim().isNotEmpty) {
      try {
        final audio = await _apiService.synthesizeSpeech(
          fullText,
          voiceId: _ttsVoiceId,
          stability: _ttsStability,
          similarityBoost: _ttsSimilarityBoost,
        );
        await _player.play(BytesSource(audio));
      } catch (e) {
        // Don't fail the reply over voice playback; tell the user once.
        if (mounted && !_ttsWarned) {
          _ttsWarned = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', '')),
            ),
          );
        }
      }
    }
    await loadThemeFromSupabase();
    if (mounted) setState(() => _loadCategories());
  }

  void _handleSendError(Object e) {
    if (!mounted) return;
    if (e is SessionExpiredException) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } else {
      setState(() {
        _messages.add(ChatMessage(
            text: 'Error: ${e.toString()}', isUser: false, isError: true));
      });
    }
  }

  /// Maps a raw tool name to a friendly "working…" chip label.
  String _toolLabel(String? name) {
    switch (name) {
      case 'list_categories':
        return 'Looking through your categories…';
      case 'get_items':
        return 'Checking your inventory…';
      case 'get_fields':
        return 'Reading the category setup…';
      case 'create_category':
        return 'Creating the category…';
      case 'rename_category':
        return 'Renaming the category…';
      case 'delete_category':
        return 'Deleting the category…';
      case 'add_field':
        return 'Adding the field…';
      case 'remove_field':
        return 'Removing the field…';
      case 'rename_field':
        return 'Updating the field…';
      case 'upsert_item':
        return 'Saving the item…';
      case 'delete_item':
        return 'Deleting the item…';
      case 'get_ui_settings':
        return 'Checking your settings…';
      case 'set_ui_setting':
        return 'Updating your settings…';
      case 'set_layout':
        return 'Adjusting the layout…';
      default:
        return 'Working…';
    }
  }

  /// Auto-scroll to the bottom on streamed tokens, but only if the user is
  /// already near the bottom — never yank them while they've scrolled up.
  void _maybeAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.maxScrollExtent - pos.pixels < 160) {
        _scrollController.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    await _player.stop();
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
                await _apiService.createCategory(name, icon);
                setState(() => _loadCategories());
              },
            ),
          );
        },
      ),
    );
  }

  /// Opens the create-category flow directly (same sheet "Manage Categories"
  /// uses for "+ New Category"), so it's reachable in one tap from the drawer.
  void _showNewCategorySheet() {
    Navigator.pop(context); // close drawer
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NewCategorySheet(
        onCreated: (name, icon) async {
          await _apiService.createCategory(name, icon);
          setState(() => _loadCategories());
        },
      ),
    );
  }

  Widget _buildDrawer() {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: scheme.surface,
      child: Column(
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
                  gradient: AppStyle.accentGradient(scheme),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: CustomPaint(
                        painter: _StockAICubeLogoPainter(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'StockAI',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              letterSpacing: 0.2,
                            ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'CATEGORIES',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                      color: AppStyle.textFaint,
                    ),
                  ),
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
                        // Strip leading emoji + whitespace from display_name (emoji shown in leading)
                        final displayName = isEmoji
                            ? name.replaceFirst(
                                RegExp(r'^\p{Emoji_Presentation}\s*', unicode: true), '')
                            : name;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            leading: Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                    color: scheme.primary
                                        .withValues(alpha: 0.22)),
                              ),
                              child: isEmoji
                                  ? Text(icon,
                                      style: const TextStyle(fontSize: 18))
                                  : Icon(Icons.inventory_2_outlined,
                                      size: 18, color: scheme.primary),
                            ),
                            title: Text(displayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            trailing: Icon(Icons.chevron_right,
                                size: 18, color: scheme.onSurfaceVariant),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CategoryScreen(category: cat),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: scheme.primary.withValues(alpha: 0.30)),
                  ),
                  leading: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.22)),
                    ),
                    child: Icon(Icons.add, size: 18, color: scheme.primary),
                  ),
                  title: Text('New Category',
                      style: TextStyle(
                          color: scheme.primary, fontWeight: FontWeight.w600)),
                  onTap: _showNewCategorySheet,
                ),
              ),
              Divider(height: 1, color: AppStyle.hairline(scheme)),
              ListTile(
                leading: Icon(Icons.category_outlined,
                    color: scheme.onSurfaceVariant),
                title: const Text('Manage Categories'),
                onTap: _showManageCategoriesSheet,
              ),
              ListTile(
                leading: Icon(Icons.settings_outlined,
                    color: scheme.onSurfaceVariant),
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
          ),
        );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _speech.stop();
    _player.dispose();
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
        title: ShaderMask(
          shaderCallback: (rect) =>
              AppStyle.accentGradient(theme.colorScheme).createShader(rect),
          child: const Text(
            'StockAI',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
        ),
        centerTitle: true,
        elevation: 0,
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
      body: Stack(
        children: [
          // Soft accent glow behind the conversation for depth.
          const AccentGlow(
              alignment: Alignment.topCenter, radius: 260, opacity: 0.16),
          Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _sending) {
                  return _buildLiveIndicator(theme);
                }
                return _buildMessageBubble(_messages[index], theme);
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: AppStyle.hairline(theme.colorScheme)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
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
                      focusNode: _inputFocusNode,
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening…'
                            : 'Ask me anything about your inventory…',
                        filled: true,
                        fillColor: AppStyle.glassFill(theme.colorScheme),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppStyle.rPill),
                          borderSide: BorderSide(
                              color: AppStyle.hairline(theme.colorScheme)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppStyle.rPill),
                          borderSide: BorderSide(
                              color: theme.colorScheme.primary, width: 1.5),
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      maxLines: 5,
                      minLines: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildSendButton(theme),
                ],
              ),
            ),
          ),
        ],
          ),
        ],
      ),
    );
  }

  /// Circular send button (accent gradient) that becomes a stop button while
  /// speaking or streaming.
  Widget _buildSendButton(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isStop = _isSpeaking || (_sending && _streamSub != null);
    if (isStop) {
      return Container(
        decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
        child: IconButton(
          onPressed: _isSpeaking ? _stopSpeaking : _stopStreaming,
          icon: Icon(Icons.stop_rounded, color: scheme.onError),
          tooltip: _isSpeaking ? 'Stop speaking' : 'Stop',
        ),
      );
    }
    final enabled = !_sending;
    return AnimatedOpacity(
      duration: AppStyle.fast,
      opacity: enabled ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppStyle.accentGradient(scheme),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: IconButton(
          onPressed: enabled ? _sendMessage : null,
          icon: Icon(Icons.arrow_upward_rounded, color: scheme.onPrimary),
          tooltip: 'Send',
        ),
      ),
    );
  }

  /// The trailing item shown while a reply is in flight: a tool "working…"
  /// chip, the live streaming bubble, or the default "Thinking…" indicator
  /// (the last is also what the non-streaming path shows).
  Widget _buildLiveIndicator(ThemeData theme) {
    if (_toolChip != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _toolChip!,
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final streaming = _streamingText;
    if (streaming != null && streaming.isNotEmpty) {
      return _buildMessageBubble(
          ChatMessage(text: streaming, isUser: false), theme);
    }

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
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, ThemeData theme) {
    final scheme = theme.colorScheme;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppStyle.rBubble),
      topRight: const Radius.circular(AppStyle.rBubble),
      bottomLeft: Radius.circular(msg.isUser ? AppStyle.rBubble : 6),
      bottomRight: Radius.circular(msg.isUser ? 6 : AppStyle.rBubble),
    );

    final BoxDecoration decoration;
    final Color textColor;
    if (msg.isError) {
      decoration = BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: radius,
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      );
      textColor = scheme.onErrorContainer;
    } else if (msg.isUser) {
      // Sent bubble — accent gradient with a soft glow.
      decoration = BoxDecoration(
        gradient: AppStyle.accentGradient(scheme),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      );
      textColor = scheme.onPrimary;
    } else {
      // Assistant bubble — glass panel with hairline border.
      decoration = BoxDecoration(
        color: AppStyle.glassFill(scheme),
        borderRadius: radius,
        border: Border.all(color: AppStyle.hairline(scheme)),
      );
      textColor = scheme.onSurface;
    }

    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        duration: AppStyle.med,
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: 1),
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: decoration,
          child: Text(
            msg.text,
            style: TextStyle(color: textColor, fontSize: 15, height: 1.42),
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

/// Draws the StockAI cube logo — matches the SVG in landing.html:
///   hexagon outline + top-face cross-line + vertical center line.
class _StockAICubeLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // SVG viewBox 0 0 100 100 → scale to widget size
    final scaleX = size.width / 100;
    final scaleY = size.height / 100;
    Offset p(double x, double y) => Offset(x * scaleX, y * scaleY);

    // Hexagon: polygon points="50,10 90,30 90,70 50,90 10,70 10,30"
    final hex = Path()
      ..moveTo(p(50, 10).dx, p(50, 10).dy)
      ..lineTo(p(90, 30).dx, p(90, 30).dy)
      ..lineTo(p(90, 70).dx, p(90, 70).dy)
      ..lineTo(p(50, 90).dx, p(50, 90).dy)
      ..lineTo(p(10, 70).dx, p(10, 70).dy)
      ..lineTo(p(10, 30).dx, p(10, 30).dy)
      ..close();
    canvas.drawPath(hex, paint);

    // Top-face cross: polyline points="10,30 50,50 90,30"
    final cross = Path()
      ..moveTo(p(10, 30).dx, p(10, 30).dy)
      ..lineTo(p(50, 50).dx, p(50, 50).dy)
      ..lineTo(p(90, 30).dx, p(90, 30).dy);
    canvas.drawPath(cross, paint);

    // Center vertical: line x1="50" y1="50" x2="50" y2="90"
    canvas.drawLine(p(50, 50), p(50, 90), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
