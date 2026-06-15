import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  static const String _edgeFunctionUrl =
      'https://masngvxdbxqrrreszjxv.supabase.co/functions/v1/smart-api';

  /// Master switch for SSE streaming. Keep OFF until the streaming backend
  /// (smart-api `stream:true`) is deployed — when off, `sendMessage()` is used
  /// and the app behaves exactly as before. Flip to true to use `streamMessage()`.
  static const bool useStreaming = false;

  final _supabase = Supabase.instance.client;

  /// Compose the outgoing message text, optionally prepending conversation
  /// history and/or a brevity hint. Shared by [sendMessage] and [streamMessage].
  String _composeMessage(
      String message, bool concise, List<Map<String, String>> history) {
    if (history.isNotEmpty) {
      // Prepend conversation history as plain text — same format as the web client
      final historyText = history.map((m) {
        final role = m['role'] == 'user' ? 'User' : 'Assistant';
        return '$role: ${m["content"]}';
      }).join('\n');
      final concisePrefix = concise ? 'Reply in 1-2 sentences maximum.\n\n' : '';
      return '[Previous conversation:\n$historyText\n]\n\n${concisePrefix}User: $message';
    }
    // When triggered by voice, prepend a brevity hint so the AI keeps its
    // response short enough to be comfortable to listen to.
    return concise ? 'Reply in 1-2 sentences maximum.\n\n$message' : message;
  }

  /// Refresh the session and return the access token.
  /// Throws [SessionExpiredException] if the refresh token is invalid.
  Future<String> _freshToken() async {
    try {
      final authResponse = await _supabase.auth.refreshSession();
      final token = authResponse.session?.accessToken;
      if (token == null) throw SessionExpiredException();
      return token;
    } catch (e) {
      if (e is SessionExpiredException) rethrow;
      // AuthApiException with refresh_token_not_found or similar
      await _supabase.auth.signOut();
      throw SessionExpiredException();
    }
  }

  Future<String> sendMessage(
    String message, {
    bool concise = false,
    List<Map<String, String>> history = const [],
  }) async {
    final accessToken = await _freshToken();

    final finalMessage = _composeMessage(message, concise, history);

    final response = await http.post(
      Uri.parse(_edgeFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'message': finalMessage,
        'context': {
          'page': 'mobile_app',
          'tableName': null,
        },
      }),
    );

    if (response.statusCode == 401) {
      // Session expired — force re-login
      await _supabase.auth.signOut();
      throw SessionExpiredException();
    }
    if (response.statusCode != 200) {
      String detail = 'API error ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body['error'] != null) detail = body['error'] as String;
      } catch (_) {}
      throw Exception(detail);
    }

    final data = jsonDecode(response.body);
    return data['message'] ?? data['content']?[0]?['text'] ?? 'No response';
  }

  /// Streaming counterpart to [sendMessage]. Sends `stream:true` and yields
  /// [ChatEvent]s parsed from the smart-api SSE stream (see ai-streaming-contract.md):
  /// start / token / tool / turn / done / error. The caller appends `token`
  /// text live, clears the bubble on a `turn` with stop_reason "tool_use", and
  /// treats `done.message` as the canonical final answer.
  ///
  /// Throws [SessionExpiredException] on a pre-stream HTTP 401 (auth is checked
  /// before the stream opens). Mid-stream failures arrive as an `error` event.
  /// Cancelling the returned subscription closes the underlying HTTP client.
  Stream<ChatEvent> streamMessage(
    String message, {
    bool concise = false,
    List<Map<String, String>> history = const [],
  }) async* {
    final accessToken = await _freshToken();
    final finalMessage = _composeMessage(message, concise, history);

    final request = http.Request('POST', Uri.parse(_edgeFunctionUrl));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Authorization': 'Bearer $accessToken',
    });
    request.body = jsonEncode({
      'message': finalMessage,
      'context': {'page': 'mobile_app', 'tableName': null},
      'stream': true,
    });

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode == 401) {
        await _supabase.auth.signOut();
        throw SessionExpiredException();
      }
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        String detail = 'API error ${response.statusCode}';
        try {
          final json = jsonDecode(body);
          if (json['error'] != null) detail = json['error'] as String;
        } catch (_) {}
        throw Exception(detail);
      }

      // Parse the SSE stream line-by-line. Each event is an `event:` line
      // followed by a `data:` line; blank lines separate events; lines
      // starting with ':' are keep-alive comments.
      var eventName = 'message';
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) {
          eventName = 'message';
          continue;
        }
        if (line.startsWith(':')) continue; // keep-alive comment
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
          continue;
        }
        if (line.startsWith('data:')) {
          final event = ChatEvent.fromSse(eventName, line.substring(5).trim());
          if (event != null) yield event;
        }
      }
    } finally {
      client.close();
    }
  }

  Future<Uint8List> synthesizeSpeech(
    String text, {
    String voiceId = 'EXAVITQu4vr4xnSDxMaL', // Sarah — premade, free tier
    double stability = 0.5,
    double similarityBoost = 0.75,
  }) async {
    final request = http.Request(
      'POST',
      Uri.parse(
          'https://api.elevenlabs.io/v1/text-to-speech/$voiceId/stream'),
    );
    request.headers.addAll({
      'xi-api-key': 'sk_06e876556112608c5c8a65f10e043f544c869786d6df6c60',
      'Content-Type': 'application/json',
      'Accept': 'audio/mpeg',
    });
    request.body = jsonEncode({
      'text': text,
      'model_id': 'eleven_flash_v2_5',
      'voice_settings': {
        'stability': stability,
        'similarity_boost': similarityBoost,
      },
    });

    final streamedResponse = await request.send();
    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw Exception('TTS error ${streamedResponse.statusCode}: $body');
    }
    return await streamedResponse.stream.toBytes();
  }

  Future<void> deleteAccount() async {
    // Calls the delete_user_account() Postgres function directly via RPC.
    // That function runs as SECURITY INVOKER and deletes auth.users WHERE id = auth.uid(),
    // which cascades to all user data via ON DELETE CASCADE triggers.
    await _supabase.rpc('delete_user_account');
  }

  Future<void> _directToolCall(
      String toolName, Map<String, dynamic> input, String accessToken) async {
    final response = await http.post(
      Uri.parse(_edgeFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'tool_call': {'name': toolName, 'input': input}}),
    );
    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }
    // Edge function catches tool errors and returns them as a 200 with an
    // error message in the body (e.g. "❌ Error in remove_field: ...").
    // Check for this so callers see a real exception instead of silent failure.
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final result = data['result'] as String? ?? data['message'] as String? ?? '';
    if (result.startsWith('❌')) {
      throw Exception(result);
    }
  }

  Future<void> createCategory(String displayName, String icon) async {
    final token = await _freshToken();
    final tableName = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    await _directToolCall('create_category', {
      'table_name': tableName,
      'display_name': displayName,
      'icon': icon.isNotEmpty ? icon : '📦',
      'fields': [
        {'field_name': 'name', 'display_name': 'Name', 'field_type': 'text', 'required': true},
        {'field_name': 'quantity', 'display_name': 'Quantity', 'field_type': 'number', 'required': false},
      ],
    }, token);
  }

  Future<void> addField(String tableName, String fieldName, String displayName,
      String fieldType) async {
    final token = await _freshToken();
    await _directToolCall('add_field', {
      'table_name': tableName,
      'field_name': fieldName,
      'display_name': displayName,
      'field_type': fieldType,
    }, token);
  }

  Future<void> removeField(String tableName, String fieldName) async {
    final token = await _freshToken();
    await _directToolCall('remove_field', {
      'table_name': tableName,
      'field_name': fieldName,
    }, token);
  }

  Future<void> updateField(
      String tableName, String fieldName, String displayName,
      {String? newFieldType}) async {
    final token = await _freshToken();
    final input = <String, dynamic>{
      'table_name': tableName,
      'field_name': fieldName,
      'new_display_name': displayName,
      if (newFieldType != null) 'new_field_type': newFieldType,
    };
    await _directToolCall('rename_field', input, token);
  }

  Future<void> deleteCategory(String tableName) async {
    final token = await _freshToken();

    final response = await http.post(
      Uri.parse(_edgeFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'message':
            'Delete the inventory category with table name "$tableName". Proceed immediately without asking for confirmation.',
        'context': {'page': 'mobile_app', 'tableName': null},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }
  }
}

class SessionExpiredException implements Exception {
  @override
  String toString() => 'Session expired. Please log in again.';
}

/// SSE event kinds emitted by smart-api's streaming response.
enum ChatEventType { start, token, tool, turn, done, error }

/// A single parsed event from [ApiService.streamMessage].
class ChatEvent {
  final ChatEventType type;

  /// `token.text` — a delta to append to the active assistant bubble.
  final String? text;

  /// `tool.name` / `tool.status` ("running" | "done" | "error").
  final String? toolName;
  final String? toolStatus;

  /// `turn.stop_reason` ("tool_use" | "end_turn"). On "tool_use" the caller
  /// discards text streamed during that turn (pre-tool "thinking").
  final String? stopReason;

  /// `done.message` — the canonical full final answer.
  final String? message;

  /// `done.refresh` / `done.navigate`.
  final bool refresh;
  final String? navigate;

  /// `error.error` — human-readable error text.
  final String? error;

  const ChatEvent({
    required this.type,
    this.text,
    this.toolName,
    this.toolStatus,
    this.stopReason,
    this.message,
    this.refresh = false,
    this.navigate,
    this.error,
  });

  /// Parse one SSE `event:`/`data:` pair into a [ChatEvent]. Returns null for
  /// unknown event names or unparseable JSON (so the stream can skip them).
  static ChatEvent? fromSse(String event, String data) {
    Map<String, dynamic> json;
    try {
      json = data.isEmpty ? {} : jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    switch (event) {
      case 'start':
        return const ChatEvent(type: ChatEventType.start);
      case 'token':
        return ChatEvent(type: ChatEventType.token, text: json['text'] as String? ?? '');
      case 'tool':
        return ChatEvent(
          type: ChatEventType.tool,
          toolName: json['name'] as String? ?? '',
          toolStatus: json['status'] as String? ?? '',
        );
      case 'turn':
        return ChatEvent(type: ChatEventType.turn, stopReason: json['stop_reason'] as String?);
      case 'done':
        return ChatEvent(
          type: ChatEventType.done,
          message: json['message'] as String? ?? '',
          refresh: json['refresh'] == true,
          navigate: json['navigate'] as String?,
        );
      case 'error':
        return ChatEvent(type: ChatEventType.error, error: json['error'] as String? ?? 'Unknown error');
      default:
        return null;
    }
  }
}
