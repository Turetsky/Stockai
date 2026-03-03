import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await _client
        .from('table_definitions')
        .select('*')
        .order('display_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getFieldDefinitions(String tableName) async {
    final response = await _client
        .from('field_definitions')
        .select('*')
        .eq('table_name', tableName)
        .order('sort_order');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getItems(String tableName) async {
    final response = await _client
        .from(tableName)
        .select('*')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> upsertItem(String tableName, Map<String, dynamic> data) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    data['user_id'] = userId;
    await _client.from(tableName).upsert(data);
  }

  Future<void> deleteItem(String tableName, String id) async {
    await _client.from(tableName).delete().eq('id', id);
  }

  Future<Map<String, String>> getUiSettings() async {
    final response = await _client
        .from('ui_settings')
        .select('key, value');
    final result = <String, String>{};
    for (final row in response) {
      final key = row['key'] as String;
      final raw = row['value'];
      result[key] = _parseValue(raw);
    }
    return result;
  }

  Future<void> setUiSetting(String key, String value) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('ui_settings').upsert(
      {'user_id': userId, 'key': key, 'value': value},
      onConflict: 'user_id, key',
    );
  }

  String _parseValue(dynamic value) {
    if (value == null) return '';
    if (value is String) {
      // Strip surrounding JSON quotes if present (jsonb string storage)
      if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
        return value.substring(1, value.length - 1);
      }
      return value;
    }
    return value.toString();
  }
}
