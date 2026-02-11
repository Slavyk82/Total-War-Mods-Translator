import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:twmt/providers/theme_provider.dart';
import 'package:twmt/providers/data_migration_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/config/router/app_router.dart' show goRouterProvider, rootNavigatorKey;
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/features/settings/providers/update_providers.dart';
import 'package:twmt/features/release_notes/providers/release_notes_providers.dart';
import 'package:twmt/features/release_notes/widgets/release_notes_dialog.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/dialogs/data_migration_dialog.dart';

void main() async {
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

  // Register app lifecycle observer for proper cleanup
  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeAsync = ref.watch(themeProvider);
    final router = ref.watch(goRouterProvider);

    return themeModeAsync.when(
      data: (themeMode) => MaterialApp.router(
        title: 'TWMT',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        routerConfig: router,
        builder: (context, child) => _AppStartupTasks(child: child!),
      ),
      loading: () => MaterialApp(
        home: Scaffold(
          body: Center(
            child: FluentSpinner(),
          ),
        ),
      ),
      error: (error, stack) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Error loading theme: $error'),
          ),
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
    // Wait a moment for UI to be ready
    await Future.delayed(const Duration(milliseconds: 500));
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

    // After migrations, continue with other startup tasks
    if (!mounted) return;
    _continueStartupTasks();
  }

  void _continueStartupTasks() {
    // Trigger auto-update check directly
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        ref.read(updateCheckerProvider.notifier).checkForUpdates();
      }
    });

    // Check for release notes after update check
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _checkReleaseNotes();
      }
    });

    // Trigger cleanup of old installer files
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
