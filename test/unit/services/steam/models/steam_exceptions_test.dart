import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';

void main() {
  test('base SteamServiceException formats code + message', () {
    const e = SteamServiceException('boom', code: 'X');
    expect(e.code, 'X');
    expect(e.toString(), 'SteamServiceException(X): boom');
  });

  test('each subtype carries its documented code', () {
    final cases = <SteamServiceException, String>{
      const SteamCmdNotFoundException('m'): 'STEAMCMD_NOT_FOUND',
      const SteamCmdDownloadException('m'): 'STEAMCMD_DOWNLOAD_FAILED',
      const SteamCmdInitializationException('m'): 'STEAMCMD_INIT_FAILED',
      const WorkshopDownloadException('m', workshopId: '1'):
          'WORKSHOP_DOWNLOAD_FAILED',
      const WorkshopApiException('m', statusCode: 500): 'WORKSHOP_API_FAILED',
      const WorkshopModNotFoundException('m', workshopId: '1'):
          'WORKSHOP_MOD_NOT_FOUND',
      const InvalidWorkshopIdException('m', invalidId: 'bad'):
          'INVALID_WORKSHOP_ID',
      const SteamCmdTimeoutException('m', timeoutSeconds: 30): 'STEAMCMD_TIMEOUT',
      const SteamAuthenticationException('m'): 'STEAM_AUTH_FAILED',
      const WorkshopPublishException('m', workshopId: '1'):
          'WORKSHOP_PUBLISH_FAILED',
      const SteamGuardRequiredException('m'): 'STEAM_GUARD_REQUIRED',
      const WorkshopItemNotFoundException('m', workshopId: '1'):
          'WORKSHOP_ITEM_NOT_FOUND',
      const VdfGenerationException('m'): 'VDF_GENERATION_FAILED',
    };

    cases.forEach((exception, expectedCode) {
      expect(exception.code, expectedCode);
      expect(exception.message, 'm');
    });
  });

  test('rich subtypes include their context in toString', () {
    expect(const WorkshopApiException('fail', workshopId: '7', statusCode: 404)
        .toString(), allOf(contains('7'), contains('404')));
    expect(const SteamCmdTimeoutException('slow', timeoutSeconds: 60).toString(),
        contains('60s'));
    expect(
      const SteamCmdNotFoundException('missing', searchedPaths: 'C:/a;C:/b')
          .toString(),
      contains('C:/a'),
    );
  });
}
