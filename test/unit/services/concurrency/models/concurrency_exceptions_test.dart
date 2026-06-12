import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/concurrency/models/concurrency_exceptions.dart';

void main() {
  test('base ConcurrencyException carries message and code', () {
    const e = ConcurrencyException('boom', code: 'X');
    expect(e.message, 'boom');
    expect(e.code, 'X');
  });

  test('each subtype sets its documented code + details', () {
    final cases = <ConcurrencyException, String>{
      TransactionException('m', transactionId: 't'): 'TRANSACTION_ERROR',
      MaxRetriesExceededException('m', maxRetries: 3, attemptsMade: 3):
          'MAX_RETRIES_EXCEEDED',
    };

    cases.forEach((exception, expectedCode) {
      expect(exception.message, 'm');
      expect(exception.code, expectedCode);
      expect(exception.details, isA<Map>());
    });
  });

  test('TransactionException stringifies the original error in details', () {
    final e = TransactionException('failed',
        transactionId: 't1', originalError: StateError('inner'));
    final details = e.details as Map;
    expect(details['transaction_id'], 't1');
    expect(details['original_error'], contains('inner'));
  });
}
