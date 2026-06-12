import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/widgets/prompt_preview_dialog.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

class _MockPromptBuilder extends Mock implements IPromptBuilderService {}

const _unit = TranslationUnit(
  id: 'unit-a',
  projectId: 'project-1',
  key: 'greeting',
  sourceText: 'Hello world',
  createdAt: 0,
  updatedAt: 0,
);

final _context = TranslationContext(
  id: 'ctx-1',
  projectId: 'project-1',
  projectLanguageId: 'plang-1',
  providerId: 'provider_anthropic',
  modelId: 'claude',
  targetLanguage: 'fr',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

BuiltPrompt _builtPrompt() => BuiltPrompt(
      systemMessage: 'SYSTEM-MESSAGE-BODY',
      userMessage: 'USER-MESSAGE-BODY',
      unitCount: 1,
      metadata: PromptMetadata(
        includesExamples: true,
        exampleCount: 2,
        includesGlossary: false,
        glossaryTermCount: 0,
        includesGameContext: false,
        includesProjectContext: false,
        estimatedTokens: 42,
        providerCode: 'anthropic',
        createdAt: DateTime(2026, 1, 1),
      ),
    );

void main() {
  late _MockPromptBuilder promptBuilder;

  setUpAll(() {
    registerFallbackValue(<TranslationUnit>[]);
    registerFallbackValue(_context);
  });

  setUp(() {
    promptBuilder = _MockPromptBuilder();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1600, 1700);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  void stubBuildPrompt(
    Future<Result<BuiltPrompt, PromptBuildingException>> Function() answer,
  ) {
    when(() => promptBuilder.buildPrompt(
          units: any(named: 'units'),
          context: any(named: 'context'),
          includeExamples: any(named: 'includeExamples'),
          maxExamples: any(named: 'maxExamples'),
        )).thenAnswer((_) => answer());
  }

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PromptPreviewDialog(unit: _unit, context: _context),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        promptBuilderServiceProvider.overrideWithValue(promptBuilder),
      ],
    ));
    await tester.tap(find.text('open'));
  }

  testWidgets('shows a spinner while the preview is building', (tester) async {
    stubBuildPrompt(
      () => Completer<Result<BuiltPrompt, PromptBuildingException>>().future,
    );

    await pumpDialog(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the error state when prompt building fails',
      (tester) async {
    stubBuildPrompt(
      () async => Err<BuiltPrompt, PromptBuildingException>(
        const PromptBuildingException('boom'),
      ),
    );

    await pumpDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('Error building prompt preview'), findsOneWidget);
  });

  testWidgets('renders unit info, tabs and the token badge on success',
      (tester) async {
    stubBuildPrompt(() async =>
        Ok<BuiltPrompt, PromptBuildingException>(_builtPrompt()));

    await pumpDialog(tester);
    await tester.pumpAndSettle();

    // Header / unit info
    expect(find.text('Prompt Preview'), findsOneWidget);
    expect(find.text('Key: greeting'), findsOneWidget);
    expect(find.textContaining('tokens'), findsOneWidget);

    // Tabs
    expect(find.text('System Prompt'), findsOneWidget);
    expect(find.text('User Message'), findsOneWidget);
    expect(find.text('API Payload'), findsOneWidget);

    // Default tab shows the system message
    expect(find.text('SYSTEM-MESSAGE-BODY'), findsOneWidget);
  });

  testWidgets('switching to the User Message tab shows the user message',
      (tester) async {
    stubBuildPrompt(() async =>
        Ok<BuiltPrompt, PromptBuildingException>(_builtPrompt()));

    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('User Message'));
    await tester.pumpAndSettle();

    expect(find.text('USER-MESSAGE-BODY'), findsOneWidget);
  });

  testWidgets('Close button dismisses the dialog', (tester) async {
    stubBuildPrompt(() async =>
        Ok<BuiltPrompt, PromptBuildingException>(_builtPrompt()));

    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Prompt Preview'), findsNothing);
  });
}
