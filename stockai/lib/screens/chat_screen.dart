import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import '../main.dart';
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

  // Voice input
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  // TTS
  final AudioPlayer _player = AudioPlayer();
  bool _isSpeaking = false;
  String _ttsVoiceId = '21m00Tcm4TlvDq8ikWAM'; // ElevenLabs Rachel (default)
  double _ttsStability = 0.5;
  double _ttsSimilarityBoost = 0.75;

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
        try {
          final audio = await _apiService.synthesizeSpeech(
            response,
            voiceId: _ttsVoiceId,
            stability: _ttsStability,
            similarityBoost: _ttsSimilarityBoost,
          );
          await _player.play(BytesSource(audio));
        } catch (_) {}
      }
      // Reload categories + theme in case the AI changed them
      await loadThemeFromSupabase();
      if (mounted) {
        setState(() {
          _loadCategories();
        });
      }
    } catch (e) {
      if (mounted) {
        if (e is SessionExpiredException) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
        } else {
          setState(() {
            _messages.add(
                ChatMessage(text: 'Error: ${e.toString()}', isUser: false, isError: true));
          });
        }
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

  Widget _buildDrawer() {
    return Drawer(
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
                        return ListTile(
                          leading: isEmoji
                              ? Text(icon,
                                  style: const TextStyle(fontSize: 22))
                              : const Icon(Icons.inventory_2_outlined),
                          title: Text(displayName),
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
          ),
        );
  }

  @override
  void dispose() {
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
        title: const Text('StockAI'),
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
                    color: Colors.black.withValues(alpha: 0.05),
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
                      focusNode: _inputFocusNode,
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
                            .withValues(alpha: 0.3),
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
