import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:twmt/providers/app_locale_provider.dart';
import 'package:twmt/providers/theme_name_provider.dart';
import 'package:twmt/providers/data_migration_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/config/router/app_router.dart' show goRouterProvider, rootNavigatorKey;
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/backup/auto_backup_service.dart';
import 'package:twmt/config/database_config.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/features/bootstrap/widgets/mod_scan_boot_dialog.dart';
import 'package:twmt/features/bootstrap/widgets/validation_rescan_dialog.dart';
import 'package:twmt/features/glossary/screens/glossary_migration_screen.dart';
import 'package:twmt/providers/update_providers.dart';
import 'package:twmt/providers/release_notes_providers.dart';
import 'package:twmt/widgets/dialogs/release_notes_dialog.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/widgets/dialogs/data_migration_dialog.dart';
import 'package:twmt/widgets/logs/log_console_overlay.dart';

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

    // Register app lifecycle observer for proper cleanup. The same instance is
    // also registered as a window_manager listener (Windows only) so that the
    // shutdown checkpoint is awaited reliably via onWindowClose rather than
    // relying on the unreliable AppLifecycleState.detached signal.
    final lifecycleObserver = _AppLifecycleObserver();
    WidgetsBinding.instance.addObserver(lifecycleObserver);
    if (Platform.isWindows) {
      windowManager.addListener(lifecycleObserver);
      // Enable prevent-close ONLY after the onWindowClose listener is attached,
      // otherwise the close button would be inert during startup (DB migrations
      // etc.) with no handler to run destroy(). This keeps the window alive
      // until _AppLifecycleObserver.onWindowClose runs an AWAITED shutdown
      // (WAL checkpoint + dispose) — more reliable than the unreliable
      // AppLifecycleState.detached signal on Windows.
      await windowManager.setPreventClose(true);
    }

    // Apply persisted app-UI locale (or fall back to device locale).
    final localePrefs = await SharedPreferences.getInstance();
    final savedLocaleCode = localePrefs.getString('twmt_app_locale');
    if (savedLocaleCode != null) {
      // Match on the full language tag (with languageCode fallback for
      // values persisted by older versions) so region-qualified locales
      // like pt-BR restore exactly instead of degrading to pt.
      await LocaleSettings.setLocale(resolveSavedAppLocale(savedLocaleCode));
    } else {
      await LocaleSettings.useDeviceLocale();
    }

    runApp(
      TranslationProvider(
        child: const ProviderScope(child: MyApp()),
      ),
    );
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
    // Force the whole app subtree to rebuild when the user switches the
    // app-UI locale. Required because every widget reads slang's global `t`
    // (not `context.t`), so nothing subscribes to TranslationProvider on
    // its own and stale strings would persist until route navigation.
    ref.watch(appLocaleProvider);

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
      builder: (context, child) => _AppStartupTasks(
        child: Stack(
          children: [
            child!,
            const LogConsoleOverlay(),
          ],
        ),
      ),
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

    // Take a rolling automatic database backup (best-effort, daily). Kicked
    // off FIRST, before the awaited release-notes network check below, so a
    // slow or hung GitHub request can never suppress the daily safety backup.
    // Runs in the background (fire-and-forget); AutoBackupService skips when a
    // recent backup already exists and prunes old archives itself.
    if (!mounted) return;
    unawaited(_runAutoBackup());

    // Trigger cleanup of old installer files.
    if (!mounted) return;
    ref.read(cleanupOldInstallersProvider);

    // Check for release notes last. This awaits a network call (now bounded by
    // AppUpdateService's request timeout); it must not gate the backup above.
    if (!mounted) return;
    await _checkReleaseNotes();
  }

  Future<void> _runAutoBackup() async {
    try {
      final backupService = ref.read(databaseBackupServiceProvider);
      final autoBackup = AutoBackupService(
        logging: ServiceLocator.get<ILoggingService>(),
        backupDirectoryProvider: () async => path.join(
          await DatabaseConfig.getAppSupportDirectory(),
          'backups',
        ),
        createBackup: backupService.createBackup,
      );
      await autoBackup.runIfDue();
    } catch (_) {
      // Best-effort; AutoBackupService logs its own failures internally.
    }
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

/// App lifecycle observer for proper resource cleanup.
///
/// Also implements [WindowListener] so that on Windows desktop the shutdown
/// cleanup (WAL checkpoint + dispose) runs AWAITED before the window/process
/// is destroyed. AppLifecycleState.detached is unreliable for this on desktop
/// (it may never fire, or fires immediately before process teardown), so the
/// window_manager onWindowClose hook — gated by setPreventClose(true) — is the
/// authoritative shutdown path. The detached handler is retained as a
/// best-effort fallback for non-desktop / non-prevent-close teardowns.
class _AppLifecycleObserver extends WidgetsBindingObserver
    with WindowListener {
  // Guards against running cleanup twice (e.g. onWindowClose then detached).
  bool _cleanupStarted = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Best-effort fallback. On Windows the awaited onWindowClose path below is
    // the reliable one; this fire-and-forget call only matters when no
    // prevent-close window handler intercepts the shutdown.
    if (state == AppLifecycleState.detached) {
      debugPrint('🧹 Application detached, cleaning up resources...');
      unawaited(_cleanupAsync());
    }
  }

  /// Window close interceptor (Windows). Because setPreventClose(true) is set,
  /// the window stays alive until we explicitly destroy it. We run the full
  /// cleanup AWAITED here so the WAL checkpoint is guaranteed to complete
  /// before the process exits.
  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      debugPrint('🧹 Window closing, running awaited cleanup...');
      await _cleanupAsync();
      // Allow the window to actually close now that cleanup is done.
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  /// Cleanup all resources before app termination. Idempotent.
  Future<void> _cleanupAsync() async {
    if (_cleanupStarted) return;
    _cleanupStarted = true;

    try {
      // Run the full shutdown checkpoint (TRUNCATE) + PRAGMA optimize and close
      // the connection via DatabaseService.close(). This is the proper clean
      // shutdown path that was previously never invoked in production.
      if (DatabaseService.isInitialized) {
        await DatabaseService.close();
        debugPrint('✅ Database closed (WAL checkpointed)');
      }
    } catch (e) {
      debugPrint('❌ Error closing database: $e');
    }

    try {
      // Dispose EventBus to close StreamController
      EventBus.instance.dispose();
      debugPrint('✅ EventBus disposed');
    } catch (e) {
      debugPrint('❌ Error disposing EventBus: $e');
    }
  }
}
