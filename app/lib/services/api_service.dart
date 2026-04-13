import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  static const String _edgeFunctionUrl =
      'https://masngvxdbxqrrreszjxv.supabase.co/functions/v1/smart-api';

  final _supabase = Supabase.instance.client;

  Future<String> sendMessage(
    String message, {
    bool concise = false,
    List<Map<String, String>> history = const [],
  }) async {
    // Use refreshSession() for a fresh JWT per CLAUDE.md critical pattern
    final authResponse = await _supabase.auth.refreshSession();
    final session = authResponse.session;
    if (session == null) throw Exception('Not authenticated');

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
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode({
        'message': finalMessage,
        'context': {
          'page': 'mobile_app',
          'tableName': null,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return data['message'] ?? data['content']?[0]?['text'] ?? 'No response';
  }

  Future<void> deleteAccount() async {
    final authResponse = await _supabase.auth.refreshSession();
    final session = authResponse.session;
    if (session == null) throw Exception('Not authenticated');

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse(_edgeFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: jsonEncode({
        'tool_call': {
          'name': 'run_sql',
          'input': {'sql': "DELETE FROM auth.users WHERE id = '$userId'"},
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete account');
    }
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

  Future<void> addField(String tableName, String fieldName, String displayName,
      String fieldType) async {
    final authResponse = await _supabase.auth.refreshSession();
    final session = authResponse.session;
    if (session == null) throw Exception('Not authenticated');
    await _directToolCall('add_field', {
      'table_name': tableName,
      'field_name': fieldName,
      'display_name': displayName,
      'field_type': fieldType,
    }, session.accessToken);
  }

  Future<void> removeField(String tableName, String fieldName) async {
    final authResponse = await _supabase.auth.refreshSession();
    final session = authResponse.session;
    if (session == null) throw Exception('Not authenticated');
    await _directToolCall('remove_field', {
      'table_name': tableName,
      'field_name': fieldName,
    }, session.accessToken);
  }

  Future<void> updateField(
      String tableName, String fieldName, String displayName,
      {String? newFieldType}) async {
    final authResponse = await _supabase.auth.refreshSession();
    final session = authResponse.session;
    if (session == null) throw Exception('Not authenticated');
    final input = <String, dynamic>{
      'table_name': tableName,
      'field_name': fieldName,
      'new_display_name': displayName,
      if (newFieldType != null) 'new_field_type': newFieldType,
    };
    await _directToolCall('rename_field', input, session.accessToken);
  }

  Future<void> deleteCategory(String tableName) async {
    final authResponse = await _supabase.auth.refreshSession();
    final session = authResponse.session;
    if (session == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse(_edgeFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${session.accessToken}',
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
