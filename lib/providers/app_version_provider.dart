import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_version_provider.g.dart';

/// Provider that fetches the application version from package info
///
/// Returns the version string (e.g., "1.0.0") from pubspec.yaml
@riverpod
Future<String> appVersion(Ref ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.version;
}
