import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../models/domain/game_installation.dart';
import '../../repositories/compilation_repository.dart';
import '../../repositories/game_installation_repository.dart';
import '../../repositories/project_repository.dart';
import '../service_locator.dart';
import '../shared/logging_service.dart';

/// Result of a single AddDependency call.
class DependencyResult {
  final String childId;
  final bool success;
  final String? error;

  const DependencyResult({
    required this.childId,
    required this.success,
    this.error,
  });
}

/// Service that sets Steam Workshop dependencies (required items) on
/// published Workshop items by calling AddDependency via a Python script
/// that loads steam_api64.dll with ctypes.
///
/// All operations are best-effort: failures are logged but never block
/// the publish flow.
class WorkshopDependencyService {
  final LoggingService _logger = LoggingService.instance;
  String? _cachedPython;

  /// Find a working Python executable, or null if unavailable.
  Future<String?> findPython() async {
    if (_cachedPython != null) return _cachedPython;

    for (final candidate in ['python', 'python3']) {
      try {
        final result = await Process.run(
          'where',
          [candidate],
          runInShell: true,
        );
        if (result.exitCode == 0 &&
            (result.stdout as String).trim().isNotEmpty) {
          _cachedPython = candidate;
          return candidate;
        }
      } catch (_) {
        // ignore – try next candidate
      }
    }
    return null;
  }

  /// Write the embedded Python script to a temporary file and return its path.
  Future<String> _getScriptPath() async {
    final tmpDir = await Directory.systemTemp.createTemp('twmt_dep_script_');
    final scriptFile = File(path.join(tmpDir.path, 'add_workshop_dependency.py'));
    await scriptFile.writeAsString(_pythonScript);
    return scriptFile.path;
  }

  /// Run the Python script to set Workshop dependencies.
  ///
  /// Returns per-child results. Throws no exceptions; all errors are
  /// captured in the returned list or logged.
  Future<List<DependencyResult>> setDependencies({
    required String dllPath,
    required String appId,
    required String parentId,
    required List<String> childIds,
  }) async {
    if (childIds.isEmpty) return [];

    final python = await findPython();
    if (python == null) {
      _logger.warning('Workshop dependencies: Python not found, skipping');
      return [];
    }

    String? scriptPath;
    try {
      scriptPath = await _getScriptPath();

      final result = await Process.run(
        python,
        [
          scriptPath,
          '--dll-path', dllPath,
          '--app-id', appId,
          '--parent-id', parentId,
          '--child-ids', childIds.join(','),
        ],
        runInShell: true,
      ).timeout(
        const Duration(minutes: 3),
        onTimeout: () => ProcessResult(-1, -1, '', 'Process timed out'),
      );

      if (result.exitCode != 0) {
        // Try to parse JSON error from stdout anyway
        final stdout = (result.stdout as String).trim();
        if (stdout.isNotEmpty) {
          try {
            final json = jsonDecode(stdout) as Map<String, dynamic>;
            if (json.containsKey('error')) {
              _logger.warning(
                'Workshop dependencies script error: ${json['error']}',
              );
              return [];
            }
          } catch (_) {
            // not valid JSON
          }
        }
        _logger.warning(
          'Workshop dependencies script exited with code ${result.exitCode}: '
          '${(result.stderr as String).trim()}',
        );
        return [];
      }

      final stdout = (result.stdout as String).trim();
      if (stdout.isEmpty) return [];

      final json = jsonDecode(stdout) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        _logger.warning('Workshop dependencies error: ${json['error']}');
        return [];
      }

      final results = (json['results'] as List<dynamic>)
          .map((e) => DependencyResult(
                childId: e['child_id'] as String,
                success: e['success'] as bool,
                error: e['error'] as String?,
              ))
          .toList();

      final successCount = results.where((r) => r.success).length;
      for (final r in results) {
        if (!r.success) {
          _logger.warning(
            'Workshop dependency failed: child=${r.childId} '
            'error=${r.error}',
          );
        }
      }
      _logger.info(
        'Workshop dependencies set: $successCount/${results.length} succeeded '
        'for parent $parentId',
      );

      return results;
    } catch (e) {
      _logger.warning('Workshop dependencies failed: $e');
      return [];
    } finally {
      // Clean up temp script
      if (scriptPath != null) {
        try {
          final scriptFile = File(scriptPath);
          final dir = scriptFile.parent;
          await scriptFile.delete();
          await dir.delete();
        } catch (_) {}
      }
    }
  }

  /// Fire-and-forget method that resolves all necessary IDs and sets
  /// Workshop dependencies after a successful publish.
  ///
  /// - For a project: parent = publishedWorkshopId, child = project.modSteamId
  /// - For a compilation: parent = publishedWorkshopId, children = all
  ///   modSteamIds from the compilation's projects
  ///
  /// Game-type projects (no modSteamId) are skipped.
  static Future<void> setDependenciesForPublishedItem({
    String? projectId,
    String? compilationId,
    required String publishedWorkshopId,
  }) async {
    final logger = LoggingService.instance;

    try {
      final service = ServiceLocator.get<WorkshopDependencyService>();
      final childIds = <String>[];
      String? gameInstallationId;

      if (projectId != null) {
        final projectRepo = ServiceLocator.get<ProjectRepository>();
        final projectResult = await projectRepo.getById(projectId);
        if (projectResult.isErr) return;
        final project = projectResult.value;

        // Game translations have no source mod dependency
        if (project.modSteamId == null || project.modSteamId!.isEmpty) return;

        childIds.add(project.modSteamId!);
        gameInstallationId = project.gameInstallationId;
      } else if (compilationId != null) {
        final compilationRepo = ServiceLocator.get<CompilationRepository>();
        final compilationResult =
            await compilationRepo.getById(compilationId);
        if (compilationResult.isErr) return;
        final compilation = compilationResult.value;
        gameInstallationId = compilation.gameInstallationId;

        // Get all projects in this compilation
        final cpResult =
            await compilationRepo.getCompilationProjects(compilationId);
        if (cpResult.isErr) return;

        final projectRepo = ServiceLocator.get<ProjectRepository>();
        for (final cp in cpResult.value) {
          final pResult = await projectRepo.getById(cp.projectId);
          if (pResult.isOk && pResult.value.modSteamId != null &&
              pResult.value.modSteamId!.isNotEmpty) {
            childIds.add(pResult.value.modSteamId!);
          }
        }
      } else {
        return;
      }

      if (childIds.isEmpty) return;

      // Resolve game installation to find DLL path and app ID
      final installRepo = ServiceLocator.get<GameInstallationRepository>();
      final installResult = await installRepo.getById(gameInstallationId);
      if (installResult.isErr) return;
      final install = installResult.value;

      final dllPath = _findSteamApiDll(install);
      if (dllPath == null) {
        logger.warning(
          'Workshop dependencies: steam_api64.dll not found for '
          '${install.gameName}',
        );
        return;
      }

      final appId = install.steamAppId;
      if (appId == null || appId.isEmpty) return;

      // Fire the actual call (already best-effort internally)
      await service.setDependencies(
        dllPath: dllPath,
        appId: appId,
        parentId: publishedWorkshopId,
        childIds: childIds,
      );
    } catch (e) {
      logger.warning('Workshop dependencies (outer): $e');
    }
  }

  /// Try to locate steam_api64.dll in the game's installation directory.
  static String? _findSteamApiDll(GameInstallation install) {
    final basePath = install.installationPath;
    if (basePath == null || basePath.isEmpty) return null;

    final dll = File(path.join(basePath, 'steam_api64.dll'));
    if (dll.existsSync()) return dll.path;

    return null;
  }
}

// ---------------------------------------------------------------------------
// Embedded Python script (avoids bundling / path resolution issues with
// Flutter desktop apps).
// ---------------------------------------------------------------------------
const String _pythonScript = r"""
import argparse
import ctypes
import json
import os
import sys
import tempfile
import time

SteamAPICall_t = ctypes.c_uint64


def load_steam_api(dll_path):
    dll = ctypes.CDLL(dll_path)

    dll.SteamAPI_Init.restype = ctypes.c_bool
    dll.SteamAPI_Init.argtypes = []

    dll.SteamAPI_Shutdown.restype = None
    dll.SteamAPI_Shutdown.argtypes = []

    dll.SteamAPI_RunCallbacks.restype = None
    dll.SteamAPI_RunCallbacks.argtypes = []

    dll.SteamAPI_ISteamUtils_IsAPICallCompleted.restype = ctypes.c_bool
    dll.SteamAPI_ISteamUtils_IsAPICallCompleted.argtypes = [
        ctypes.c_void_p,
        SteamAPICall_t,
        ctypes.POINTER(ctypes.c_bool),
    ]

    dll.SteamAPI_ISteamUGC_AddDependency.restype = SteamAPICall_t
    dll.SteamAPI_ISteamUGC_AddDependency.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint64,
        ctypes.c_uint64,
    ]

    return dll


def find_accessor(dll, prefix, versions):
    for ver in versions:
        name = f"{prefix}_v{ver}"
        try:
            func = getattr(dll, name)
            func.restype = ctypes.c_void_p
            func.argtypes = []
            ptr = func()
            if ptr:
                return ptr
        except AttributeError:
            continue
    return None


def wait_for_call(dll, utils, api_call, timeout=30.0):
    start = time.time()
    failed = ctypes.c_bool(False)
    while time.time() - start < timeout:
        dll.SteamAPI_RunCallbacks()
        if dll.SteamAPI_ISteamUtils_IsAPICallCompleted(
            utils, api_call, ctypes.byref(failed)
        ):
            return not failed.value
        time.sleep(0.1)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dll-path", required=True)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--parent-id", required=True)
    parser.add_argument("--child-ids", required=True)
    args = parser.parse_args()

    child_ids = [c.strip() for c in args.child_ids.split(",") if c.strip()]
    if not child_ids:
        json.dump({"error": "No child IDs provided"}, sys.stdout)
        sys.exit(1)

    tmp_dir = tempfile.mkdtemp(prefix="twmt_steam_dep_")
    appid_path = os.path.join(tmp_dir, "steam_appid.txt")
    original_cwd = os.getcwd()

    try:
        with open(appid_path, "w") as f:
            f.write(args.app_id)
        os.chdir(tmp_dir)

        dll = load_steam_api(args.dll_path)

        if not dll.SteamAPI_Init():
            json.dump({"error": "SteamAPI_Init failed. Is Steam running?"}, sys.stdout)
            sys.exit(1)

        try:
            ugc = find_accessor(
                dll, "SteamAPI_SteamUGC",
                ["020", "019", "018", "017", "016"],
            )
            if not ugc:
                json.dump({"error": "Could not find ISteamUGC interface"}, sys.stdout)
                sys.exit(1)

            utils = find_accessor(
                dll, "SteamAPI_SteamUtils",
                ["010", "009"],
            )
            if not utils:
                json.dump({"error": "Could not find ISteamUtils interface"}, sys.stdout)
                sys.exit(1)

            parent = int(args.parent_id)
            results = []

            for cid_str in child_ids:
                child = int(cid_str)
                entry = {"child_id": cid_str}

                api_call = dll.SteamAPI_ISteamUGC_AddDependency(ugc, parent, child)
                if api_call == 0:
                    entry["success"] = False
                    entry["error"] = "AddDependency returned invalid call handle"
                    results.append(entry)
                    continue

                completed = wait_for_call(dll, utils, api_call, timeout=30.0)
                if completed is None:
                    entry["success"] = False
                    entry["error"] = "Timeout waiting for AddDependency"
                elif completed:
                    entry["success"] = True
                else:
                    entry["success"] = False
                    entry["error"] = "API call failed"

                results.append(entry)

            json.dump({"results": results}, sys.stdout)

        finally:
            dll.SteamAPI_Shutdown()

    finally:
        os.chdir(original_cwd)
        try:
            os.remove(appid_path)
            os.rmdir(tmp_dir)
        except OSError:
            pass


if __name__ == "__main__":
    main()
""";
