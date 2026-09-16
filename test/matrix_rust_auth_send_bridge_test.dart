import 'package:flutter_test/flutter_test.dart';
import 'package:kite/matrix/matrix_outbox.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';

void main() {
  test(
    'native send transport forwards plain text with stable transaction id',
    () async {
      final client = _RecordingTextSendClient();
      final transport = MatrixRustSendTransport(client);
      final item = MatrixOutboxItem(
        localId: 'local-1',
        roomId: '!room:kite.test',
        transactionId: 'kite-txn-42',
        eventType: 'm.room.message',
        content: const <String, Object?>{
          'msgtype': 'm.text',
          'body': 'hello from Kite',
        },
        state: MatrixOutboxState.sending,
      );

      final receipt = await transport.send(item);

      expect(receipt.eventId, r'$sent');
      expect(client.roomId, '!room:kite.test');
      expect(client.body, 'hello from Kite');
      expect(client.transactionId, 'kite-txn-42');
    },
  );

  test(
    'native send transport rejects non-text content before native SDK',
    () async {
      final client = _RecordingTextSendClient();
      final transport = MatrixRustSendTransport(client);
      final item = MatrixOutboxItem(
        localId: 'local-2',
        roomId: '!room:kite.test',
        transactionId: 'kite-txn-43',
        eventType: 'm.room.message',
        content: const <String, Object?>{
          'msgtype': 'm.image',
          'body': 'not part of the E2E smoke path',
        },
        state: MatrixOutboxState.sending,
      );

      await expectLater(
        transport.send(item),
        throwsA(
          isA<MatrixSendFailure>()
              .having(
                (error) => error.code,
                'code',
                'unsupported_message_content',
              )
              .having((error) => error.retryable, 'retryable', isFalse),
        ),
      );
      expect(client.calls, 0);
    },
  );

  test(
    'native send failures map to outbox retryability without exposing detail',
    () async {
      final client = _RecordingTextSendClient(
        error: const MatrixRustNativeException(
          code: 'send_failed',
          publicMessage: 'The Matrix message could not be sent.',
        ),
      );
      final transport = MatrixRustSendTransport(client);
      final item = MatrixOutboxItem(
        localId: 'local-3',
        roomId: '!room:kite.test',
        transactionId: 'kite-txn-44',
        eventType: 'm.room.message',
        content: const <String, Object?>{
          'msgtype': 'm.text',
          'body': 'retry me',
        },
        state: MatrixOutboxState.sending,
      );

      await expectLater(
        transport.send(item),
        throwsA(
          isA<MatrixSendFailure>()
              .having((error) => error.code, 'code', 'send_failed')
              .having((error) => error.retryable, 'retryable', isTrue),
        ),
      );
    },
  );
}

final class _RecordingTextSendClient implements MatrixRustTextSendClient {
  _RecordingTextSendClient({this.error});

  final MatrixRustNativeException? error;
  int calls = 0;
  String? roomId;
  String? body;
  String? transactionId;

  @override
  Future<MatrixSendReceipt> sendText({
    required String roomId,
    required String body,
    required String transactionId,
  }) async {
    calls += 1;
    this.roomId = roomId;
    this.body = body;
    this.transactionId = transactionId;
    final error = this.error;
    if (error != null) throw error;
    return const MatrixSendReceipt(eventId: r'$sent');
  }
}
