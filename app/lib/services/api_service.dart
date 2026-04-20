import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  static const String _edgeFunctionUrl =
      'https://masngvxdbxqrrreszjxv.supabase.co/functions/v1/smart-api';

  final _supabase = Supabase.instance.client;

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

    String finalMessage;
    if (history.isNotEmpty) {
      // Prepend conversation history as plain text — same format as the web client
      final historyText = history.map((m) {
        final role = m['role'] == 'user' ? 'User' : 'Assistant';
        return '$role: ${m["content"]}';
      }).join('\n');
      final concisePrefix = concise ? 'Reply in 1-2 sentences maximum.\n\n' : '';
      finalMessage = '[Previous conversation:\n$historyText\n]\n\n${concisePrefix}User: $message';
    } else {
      // When triggered by voice, prepend a brevity hint so the AI keeps its
      // response short enough to be comfortable to listen to.
      finalMessage = concise
          ? 'Reply in 1-2 sentences maximum.\n\n$message'
          : message;
    }

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
