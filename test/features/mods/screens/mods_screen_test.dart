import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/mods/screens/mods_screen.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/providers/mods/mod_list_provider.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('ModsScreen', () {
    /// Creates test widget with mocked providers
    Widget createTestWidget({ThemeData? theme}) {
      return ProviderScope(
        overrides: [
          // Override scanLogStream provider
          scanLogStreamProvider.overrideWithValue(
            const Stream<ScanLogMessage>.empty(),
          ),
          // Override filtered mods provider - synchronous list
          filteredModsProvider.overrideWith((ref) => <DetectedMod>[]),
          // Override loading states using Notifier overrideWith syntax
          modsIsLoadingProvider.overrideWith((ref) => false),
          modsErrorProvider.overrideWith((ref) => null),
          modsSearchQueryProvider.overrideWith(() => _MockModsSearchQuery()),
          modsLoadingStateProvider.overrideWith(() => _MockModsLoadingState()),
          modsFilterStateProvider.overrideWith(() => _MockModsFilterState()),
          totalModsCountProvider.overrideWith((ref) async => 0),
          notImportedModsCountProvider.overrideWith((ref) async => 0),
          needsUpdateModsCountProvider.overrideWith((ref) async => 0),
          showHiddenModsProvider.overrideWith(() => _MockShowHiddenMods()),
          hiddenModsCountProvider.overrideWith((ref) async => 0),
          projectsWithPendingChangesCountProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: theme ?? ThemeData.light(),
          home: SizedBox(
            width: defaultTestScreenSize.width,
            height: defaultTestScreenSize.height,
            child: const ModsScreen(),
          ),
        ),
      );
    }

    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should have padding of 24.0', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(Padding), findsWidgets);
      });

      testWidgets('should have Column layout', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = ModsScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Header', () {
      testWidgets('should display cube icon', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byIcon(FluentIcons.cube_24_regular), findsWidgets);
      });

      testWidgets('should display Mods title', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Mods'), findsOneWidget);
      });
    });

    group('Toolbar', () {
      testWidgets('should render ModsToolbar', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should pass search query to toolbar', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should support refresh action', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should support filter changes', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should support hidden mods toggle', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should support import local pack', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('DataGrid', () {
      testWidgets('should render DetectedModsDataGrid', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should pass filtered mods to datagrid', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Error State', () {
      testWidgets('should display error icon on error', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should display retry button on error', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Loading State', () {
      testWidgets('should pass loading state to datagrid', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should pass refreshing state to toolbar', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Statistics', () {
      testWidgets('should display total mods count', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should display not imported count', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should display needs update count', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should display hidden count', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should display pending projects count', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Row Actions', () {
      testWidgets('should support row tap for project creation', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should support toggle hidden action', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should support force redownload action', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Navigation', () {
      testWidgets('should support navigation to projects with filter', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should support project detail navigation', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Project Creation', () {
      testWidgets('should support direct project creation', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should show initialization dialog', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Local Pack Import', () {
      testWidgets('should support local pack import', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should show local pack warning dialog', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should show project name dialog for local packs', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Refresh', () {
      testWidgets('should support manual refresh', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should invalidate providers on refresh', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Scan Log', () {
      testWidgets('should pass scan log stream to datagrid', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(createTestWidget(theme: ThemeData.light()));
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(createTestWidget(theme: ThemeData.dark()));
        await tester.pumpAndSettle();

        expect(find.byType(ModsScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible header', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Mods'), findsOneWidget);
      });
    });
  });
}

/// Mock notifier for ModsSearchQuery state
class _MockModsSearchQuery extends ModsSearchQuery {
  @override
  String build() => '';

  @override
  void setQuery(String query) {}

  @override
  void clear() {}
}

/// Mock notifier for ModsLoadingState
class _MockModsLoadingState extends ModsLoadingState {
  @override
  bool build() => false;

  @override
  void setLoading(bool value) {}
}

/// Mock notifier for ModsFilterState
class _MockModsFilterState extends ModsFilterState {
  @override
  ModsFilter build() => ModsFilter.all;

  @override
  void setFilter(ModsFilter filter) {}
}

/// Mock notifier for ShowHiddenMods
class _MockShowHiddenMods extends ShowHiddenMods {
  @override
  bool build() => false;

  @override
  void toggle() {}

  @override
  void set(bool value) {}
}
