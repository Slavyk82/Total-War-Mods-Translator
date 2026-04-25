import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:twmt/providers/theme_name_provider.dart';
import 'package:twmt/providers/data_migration_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/config/router/app_router.dart' show goRouterProvider, rootNavigatorKey;
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/features/bootstrap/widgets/mod_scan_boot_dialog.dart';
import 'package:twmt/features/bootstrap/widgets/validation_rescan_dialog.dart';
import 'package:twmt/features/glossary/screens/glossary_migration_screen.dart';
import 'package:twmt/features/settings/providers/update_providers.dart';
import 'package:twmt/features/release_notes/providers/release_notes_providers.dart';
import 'package:twmt/features/release_notes/widgets/release_notes_dialog.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/widgets/dialogs/data_migration_dialog.dart';

void main() async {
  // Everything that touches the Flutter bindings must run inside the same
  // zone. `WidgetsFlutterBinding.ensureInitialized()` and `runApp` both bind
  // to the active zone; splitting them across zones triggers a framework
  // assertion ("Zone mismatch"). We therefore run the entire bootstrap
  // inside `runZonedGuarded` so the zoned error handler is active from the
  // first binding call through to `runApp`.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (Platform.isWindows) {
      // Initialize SQLite FFI for Windows
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      // Initialize window manager
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1725, 975),
        minimumSize: Size(1725, 975),
        center: true,
        title: 'TWMT - Total War Mods Translator',
        titleBarStyle: TitleBarStyle.normal,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }

    // Initialize all services via Service Locator
    try {
      await ServiceLocator.initialize();
      debugPrint('✅ Application initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Application initialization error: $e');
      debugPrint('$stackTrace');
      // Handle error appropriately (show error dialog, etc.)
      rethrow;
    }

    // Install global error handlers. Must run AFTER ServiceLocator.initialize()
    // so ILoggingService is available.
    final logger = ServiceLocator.get<ILoggingService>();

    FlutterError.onError = (FlutterErrorDetails details) {
      logger.error(
        'Uncaught Flutter framework error',
        details.exception,
        details.stack,
      );
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      logger.error('Uncaught platform error', error, stack);
      return true;
    };

    // Register app lifecycle observer for proper cleanup
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

    runApp(const ProviderScope(child: MyApp()));
  }, (Object error, StackTrace stack) {
    // If ServiceLocator already initialized, route through the logger;
    // otherwise fall back to debugPrint so early errors are not swallowed.
    if (ServiceLocator.isInitialized) {
      ServiceLocator.get<ILoggingService>()
          .error('Uncaught zoned error', error, stack);
    } else {
      debugPrint('Uncaught zoned error (pre-DI): $error\n$stack');
    }
  });
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeNameAsync = ref.watch(themeNameProvider);
    final router = ref.watch(goRouterProvider);

    // Fall back to Atelier while the saved theme name is loading — avoids
    // a flash on first frames. All palettes except Vellum are dark; the
    // builder in AppTheme handles the brightness switch.
    final themeName = themeNameAsync.value ?? TwmtThemeName.atelier;
    final ThemeData theme = switch (themeName) {
      TwmtThemeName.atelier => AppTheme.atelierDarkTheme,
      TwmtThemeName.forge => AppTheme.forgeDarkTheme,
      TwmtThemeName.slate => AppTheme.slateDarkTheme,
      TwmtThemeName.vellum => AppTheme.vellumLightTheme,
      TwmtThemeName.warpstone => AppTheme.warpstoneDarkTheme,
      TwmtThemeName.shogun => AppTheme.shogunDarkTheme,
    };

    return MaterialApp.router(
      title: 'TWMT',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      builder: (context, child) => _AppStartupTasks(child: child!),
    );
  }
}

/// Widget that triggers startup tasks like auto-update check and cleanup.
class _AppStartupTasks extends ConsumerStatefulWidget {
  final Widget child;

  const _AppStartupTasks({required this.child});

  @override
  ConsumerState<_AppStartupTasks> createState() => _AppStartupTasksState();
}

class _AppStartupTasksState extends ConsumerState<_AppStartupTasks> {
  bool _tasksTriggered = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tasksTriggered) {
        _tasksTriggered = true;
        _triggerStartupTasks();
      }
    });
  }

  void _triggerStartupTasks() {
    // First: Check and run data migrations (with modal)
    _runDataMigrations();
  }

  Future<void> _runDataMigrations() async {
    if (!mounted) return;

    // Check if migrations are needed
    final needsMigration =
        await ref.read(dataMigrationProvider.notifier).needsMigration();

    if (needsMigration) {
      final navigatorContext = rootNavigatorKey.currentContext;
      if (navigatorContext != null && navigatorContext.mounted) {
        // Show migration dialog and wait for it to complete
        await showDialog<void>(
          context: navigatorContext,
          barrierDismissible: false,
          barrierColor: Colors.black87,
          builder: (context) => const DataMigrationDialog(),
        );
      }
    }

    // After schema migrations, check whether the glossary schema still
    // has universal or duplicate entries that require user decisions.
    // If so, block bootstrap behind a popup dialog until resolved.
    if (!mounted) return;
    final migrationService = ref.read(glossaryMigrationServiceProvider);
    final pending = await migrationService.detectPendingMigration();
    if (pending != null && mounted) {
      final glossaryContext = rootNavigatorKey.currentContext;
      if (glossaryContext != null && glossaryContext.mounted) {
        await showDialog<void>(
          context: glossaryContext,
          barrierDismissible: false,
          barrierColor: Colors.black87,
          builder: (ctx) => GlossaryMigrationScreen(
            pending: pending,
            onDone: () => Navigator.of(ctx).pop(),
          ),
        );
      }
    }

    // After schema migrations, force a one-shot structured validation
    // rescan. The dialog closes itself immediately when there is nothing
    // to migrate, so fresh installs and already-migrated DBs pay zero cost.
    if (!mounted) return;
    final rescanContext = rootNavigatorKey.currentContext;
    if (rescanContext != null && rescanContext.mounted) {
      await ValidationRescanDialog.showAndRun(rescanContext, ref);
    }

    // Run the Workshop mods scan up-front (with a progress popup) so the
    // Home dashboard cards reflect fresh counts on the very first frame the
    // user sees, instead of waiting for the Mods screen to be opened.
    if (!mounted) return;
    final modScanContext = rootNavigatorKey.currentContext;
    if (modScanContext != null && modScanContext.mounted) {
      await ModScanBootDialog.showAndRun(modScanContext, ref);
    }

    // After migrations, continue with other startup tasks
    if (!mounted) return;
    unawaited(_continueStartupTasks());
  }

  Future<void> _continueStartupTasks() async {
    // Trigger auto-update check (no delay: post-frame already fired).
    if (!mounted) return;
    unawaited(
      ref.read(updateCheckerProvider.notifier).checkForUpdates(),
    );

    // Check for release notes straight after.
    if (!mounted) return;
    await _checkReleaseNotes();

    // Trigger cleanup of old installer files.
    if (!mounted) return;
    ref.read(cleanupOldInstallersProvider);
  }

  Future<void> _checkReleaseNotes() async {
    debugPrint('[ReleaseNotes] Starting check...');
    await ref.read(releaseNotesCheckerProvider.notifier).checkReleaseNotes();

    final state = ref.read(releaseNotesCheckerProvider);
    debugPrint('[ReleaseNotes] State: isChecking=${state.isChecking}, releaseToShow=${state.releaseToShow?.version}, hasBeenDismissed=${state.hasBeenDismissed}, shouldShowDialog=${state.shouldShowDialog}');

    if (state.shouldShowDialog && mounted) {
      final navigatorContext = rootNavigatorKey.currentContext;
      if (navigatorContext != null) {
        debugPrint('[ReleaseNotes] Showing dialog!');
        showDialog(
          // ignore: use_build_context_synchronously
          context: navigatorContext,
          barrierDismissible: true,
          builder: (context) => ReleaseNotesDialog(
            release: state.releaseToShow!,
          ),
        );
      } else {
        debugPrint('[ReleaseNotes] Navigator context not available');
      }
    } else {
      debugPrint('[ReleaseNotes] Not showing dialog - shouldShowDialog=${state.shouldShowDialog}, mounted=$mounted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// App lifecycle observer for proper resource cleanup
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Clean up resources when app is being terminated
    if (state == AppLifecycleState.detached) {
      debugPrint('🧹 Application shutting down, cleaning up resources...');
      _cleanupAsync();
    }
  }

  /// Cleanup all resources before app termination
  Future<void> _cleanupAsync() async {
    try {
      // Checkpoint WAL before closing - await to ensure completion
      if (DatabaseService.isInitialized) {
        await DatabaseService.checkpointWal();
        debugPrint('✅ Database WAL checkpointed');
      }
    } catch (e) {
      debugPrint('❌ Error checkpointing WAL: $e');
    }

    try {
      // Dispose EventBus to close StreamController
      EventBus.instance.dispose();
      debugPrint('✅ EventBus disposed');
    } catch (e) {
      debugPrint('❌ Error disposing EventBus: $e');
    }

    // Additional cleanup can be added here
    // e.g., ServiceLocator.dispose(), database close, etc.
  }
}
