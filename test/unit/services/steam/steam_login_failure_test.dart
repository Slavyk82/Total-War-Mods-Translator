import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/steam/workshop_publish_service_impl.dart'
    show
        isSteamLoginFailureOutput,
        classifySteamLoginFailure,
        SteamLoginFailureKind;

/// Regression tests for the stale-steamcmd-credentials recovery path. A cached
/// login (built as `+login <user> +quit`, no password / no Steam Guard code)
/// that fails against an invalidated Steam session used to surface a hard,
/// non-retryable SteamAuthenticationException — leaving the user stuck on the
/// failing cached path with no way to re-authenticate. A failure on the cached
/// path must instead be classified as a stale cache that needs re-auth.
void main() {
  group('isSteamLoginFailureOutput', () {
    test('detects the known steamcmd login-failure markers', () {
      expect(isSteamLoginFailureOutput('Logging in...\nLogin Failure: ...'),
          isTrue);
      expect(isSteamLoginFailureOutput('FAILED login (Invalid Password)'),
          isTrue);
      expect(isSteamLoginFailureOutput('Invalid Password'), isTrue);
    });

    test('returns false for a successful upload log', () {
      expect(
        isSteamLoginFailureOutput(
            'Waiting for user info...OK\nSuccess. Published item 12345'),
        isFalse,
      );
    });
  });

  group('classifySteamLoginFailure', () {
    test('a failure on the cached-login path is a stale cache needing re-auth',
        () {
      expect(
        classifySteamLoginFailure(usedCachedLogin: true),
        SteamLoginFailureKind.staleCacheNeedsReauth,
      );
    });

    test('a failure on a full credential login is bad credentials', () {
      expect(
        classifySteamLoginFailure(usedCachedLogin: false),
        SteamLoginFailureKind.badCredentials,
      );
    });
  });
}
