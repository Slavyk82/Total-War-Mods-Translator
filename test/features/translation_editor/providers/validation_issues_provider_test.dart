import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/providers/validation_issues_provider.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/validation/i_translation_validation_service.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockValidationService extends Mock
    implements ITranslationValidationService {}

class _RecordingLogger extends FakeLogger {
  final List<String> errors = [];
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    errors.add(message);
  }
}

const _issue = ValidationIssue(
  type: ValidationIssueType.missingVariables,
  severity: ValidationSeverity.error,
  description: 'missing %s',
);

void main() {
  late _MockValidationService service;

  setUp(() {
    service = _MockValidationService();
  });

  ProviderContainer makeContainer({_RecordingLogger? logger}) {
    final container = ProviderContainer(
      overrides: [
        translationValidationServiceProvider.overrideWithValue(service),
        loggingServiceProvider.overrideWithValue(logger ?? FakeLogger()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('returns the issues reported by the validation service', () async {
    when(() => service.validateTranslation(
          sourceText: 'Hello',
          translatedText: 'Bonjour',
        )).thenAnswer(
      (_) async => const Ok<List<ValidationIssue>, ServiceException>([_issue]),
    );

    final container = makeContainer();
    final issues = await container
        .read(validationIssuesProvider('Hello', 'Bonjour').future);

    expect(issues, [_issue]);
  });

  test('returns an empty list and logs when validation fails', () async {
    when(() => service.validateTranslation(
          sourceText: any(named: 'sourceText'),
          translatedText: any(named: 'translatedText'),
        )).thenAnswer(
      (_) async => const Err<List<ValidationIssue>, ServiceException>(
        ServiceException('validator offline'),
      ),
    );

    final logger = _RecordingLogger();
    final container = makeContainer(logger: logger);
    final issues =
        await container.read(validationIssuesProvider('a', 'b').future);

    expect(issues, isEmpty);
    expect(logger.errors, isNotEmpty);
  });
}
