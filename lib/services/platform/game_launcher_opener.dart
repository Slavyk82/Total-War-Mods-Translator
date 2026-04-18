import 'package:url_launcher/url_launcher.dart';

/// Builds a `steam://run/<appId>` URI.
///
/// When launched, the URI asks the Steam client to start the game associated
/// with [appId] (and, for games that own in-game Workshop uploaders, brings
/// that launcher to the foreground).
Uri buildSteamRunUri(String appId) {
  if (appId.trim().isEmpty) {
    throw ArgumentError('appId must not be empty');
  }
  return Uri.parse('steam://run/$appId');
}

/// Opens the game launcher for [appId] via the Steam client.
///
/// Returns `true` if the launch was dispatched, `false` if the platform
/// cannot handle `steam://` URIs (e.g. Steam is not installed).
Future<bool> openGameLauncher(String appId) async {
  final uri = buildSteamRunUri(appId);
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri);
}
