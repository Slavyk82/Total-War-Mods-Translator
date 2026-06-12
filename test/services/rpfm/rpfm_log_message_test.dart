import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';

void main() {
  test('defaults the timestamp to now when omitted', () {
    final before = DateTime.now();
    final msg = RpfmLogMessage(message: 'extracting');
    final after = DateTime.now();

    expect(msg.message, 'extracting');
    expect(
      msg.timestamp.isBefore(before.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      msg.timestamp.isAfter(after.add(const Duration(seconds: 1))),
      isFalse,
    );
  });

  test('keeps an explicitly provided timestamp', () {
    final ts = DateTime.fromMillisecondsSinceEpoch(5000);
    final msg = RpfmLogMessage(message: 'done', timestamp: ts);
    expect(msg.timestamp, ts);
  });
}
