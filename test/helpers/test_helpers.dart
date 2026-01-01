import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/repositories/game_installation_repository.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/models/common/result.dart' show Ok;
import 'package:twmt/models/domain/game_installation.dart';

/// Mock class for GameInstallationRepository
class MockGameInstallationRepository extends Mock
    implements GameInstallationRepository {}

/// Mock class for ProjectRepository
class MockProjectRepository extends Mock implements ProjectRepository {}

/// Sets up mock services for tests that require ServiceLocator
/// Call this in setUp() of your test files that test screens using ServiceLocator
Future<void> setupMockServices() async {
  final getIt = GetIt.instance;

  // Reset any existing registrations
  await getIt.reset();

  // Create and register mock GameInstallationRepository
  final mockGameInstallationRepo = MockGameInstallationRepository();
  when(() => mockGameInstallationRepo.getAll()).thenAnswer(
    (_) async => const Ok(<GameInstallation>[]),
  );

  // Create and register mock ProjectRepository
  final mockProjectRepo = MockProjectRepository();
  when(() => mockProjectRepo.clearModUpdateImpact(any())).thenAnswer(
    (_) async => const Ok(null),
  );

  getIt.registerSingleton<GameInstallationRepository>(mockGameInstallationRepo);
  getIt.registerSingleton<ProjectRepository>(mockProjectRepo);
}

/// Cleans up mock services after tests
/// Call this in tearDown() of your test files
Future<void> tearDownMockServices() async {
  await GetIt.instance.reset();
}

/// Default screen size for tests to prevent layout overflow
const Size defaultTestScreenSize = Size(1920, 1080);

/// Creates a testable widget wrapped with necessary providers
/// Uses a SizedBox constraint to prevent layout overflow errors in tests
Widget createTestableWidget(Widget child, {List<Override>? overrides, Size? screenSize}) {
  final size = screenSize ?? defaultTestScreenSize;
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(
      home: SizedBox(
        width: size.width,
        height: size.height,
        child: child,
      ),
    ),
  );
}

/// Creates a testable widget with a Scaffold wrapper
Widget createTestableWidgetWithScaffold(Widget child,
    {List<Override>? overrides, Size? screenSize}) {
  final size = screenSize ?? defaultTestScreenSize;
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(
      home: SizedBox(
        width: size.width,
        height: size.height,
        child: Scaffold(body: child),
      ),
    ),
  );
}

/// Creates a testable widget with custom theme
Widget createThemedTestableWidget(
  Widget child, {
  List<Override>? overrides,
  ThemeData? theme,
  Size? screenSize,
}) {
  final size = screenSize ?? defaultTestScreenSize;
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(
      theme: theme ?? ThemeData.light(),
      home: SizedBox(
        width: size.width,
        height: size.height,
        child: child,
      ),
    ),
  );
}

/// Pumps widget and settles all animations
Future<void> pumpAndSettleHelper(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

/// Finds a widget by key
Finder findByKey(String key) => find.byKey(Key(key));

/// Finds a widget containing specific text
Finder findByTextContaining(String text) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.data?.contains(text) == true,
    );

/// Extension to simplify common test patterns
extension WidgetTesterExtension on WidgetTester {
  /// Pumps the widget and waits for it to settle
  Future<void> pumpWidgetAndSettle(Widget widget) async {
    await pumpWidget(widget);
    await pumpAndSettle(const Duration(milliseconds: 100));
  }
}
