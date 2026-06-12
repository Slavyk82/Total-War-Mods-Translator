import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/i_llm_service.dart';

void main() {
  ProviderStatistics stats({
    int total = 0,
    int success = 0,
    int input = 0,
    int output = 0,
  }) {
    return ProviderStatistics(
      providerCode: 'anthropic',
      totalRequests: total,
      successfulRequests: success,
      failedRequests: total - success,
      totalInputTokens: input,
      totalOutputTokens: output,
      averageResponseTimeMs: 12.5,
      fromDate: DateTime.fromMillisecondsSinceEpoch(0),
      toDate: DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  test('successRate is the ratio of successful to total requests', () {
    expect(stats(total: 4, success: 3).successRate, closeTo(0.75, 1e-9));
  });

  test('successRate is 0 when there are no requests', () {
    expect(stats().successRate, 0.0);
  });

  test('totalTokens sums input and output tokens', () {
    expect(stats(input: 100, output: 50).totalTokens, 150);
  });

  test('toString includes provider, success percent and token total', () {
    final s = stats(total: 2, success: 1, input: 10, output: 10).toString();
    expect(s, contains('anthropic'));
    expect(s, contains('50.0%'));
    expect(s, contains('20 tokens'));
  });
}
