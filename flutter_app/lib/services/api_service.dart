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
