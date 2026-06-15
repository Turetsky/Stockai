import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/services/api_service.dart';

void main() {
  group('ChatEvent.fromSse (smart-api streaming contract)', () {
    test('start', () {
      final e = ChatEvent.fromSse('start', '{}');
      expect(e!.type, ChatEventType.start);
    });

    test('token carries the text delta', () {
      final e = ChatEvent.fromSse('token', '{"text":"Hello "}');
      expect(e!.type, ChatEventType.token);
      expect(e.text, 'Hello ');
    });

    test('tool carries name + status', () {
      final e = ChatEvent.fromSse('tool', '{"name":"get_items","status":"running"}');
      expect(e!.type, ChatEventType.tool);
      expect(e.toolName, 'get_items');
      expect(e.toolStatus, 'running');
    });

    test('turn carries stop_reason (tool_use → reset signal)', () {
      final e = ChatEvent.fromSse('turn', '{"index":0,"stop_reason":"tool_use"}');
      expect(e!.type, ChatEventType.turn);
      expect(e.stopReason, 'tool_use');
    });

    test('done carries canonical message + refresh/navigate', () {
      final e = ChatEvent.fromSse(
          'done', '{"message":"All set!","refresh":true,"navigate":null}');
      expect(e!.type, ChatEventType.done);
      expect(e.message, 'All set!');
      expect(e.refresh, isTrue);
      expect(e.navigate, isNull);
    });

    test('done defaults: missing refresh is false', () {
      final e = ChatEvent.fromSse('done', '{"message":"hi"}');
      expect(e!.refresh, isFalse);
    });

    test('error carries the error text', () {
      final e = ChatEvent.fromSse('error', '{"error":"boom"}');
      expect(e!.type, ChatEventType.error);
      expect(e.error, 'boom');
    });

    test('unknown event name → null (skipped)', () {
      expect(ChatEvent.fromSse('keep-alive', '{}'), isNull);
    });

    test('malformed JSON → null (skipped, never throws)', () {
      expect(ChatEvent.fromSse('token', 'not json'), isNull);
    });

    test('missing fields fall back to safe defaults', () {
      final token = ChatEvent.fromSse('token', '{}');
      expect(token!.text, '');
      final err = ChatEvent.fromSse('error', '{}');
      expect(err!.error, 'Unknown error');
    });
  });
}
