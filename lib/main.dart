import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:twmt/providers/theme_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/event_bus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    // Initialize SQLite FFI for Windows
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Initialize window manager
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1400, 850),
      minimumSize: Size(1280, 720),
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
      ),
      loading: () => MaterialApp(
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
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

/// App lifecycle observer for proper resource cleanup
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Clean up resources when app is being terminated
    if (state == AppLifecycleState.detached) {
      debugPrint('🧹 Application shutting down, cleaning up resources...');
      _cleanup();
    }
  }

  /// Cleanup all resources before app termination
  void _cleanup() {
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
