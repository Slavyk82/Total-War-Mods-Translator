import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/models/workshop_publish_result.dart';

/// Service interface for publishing items to Steam Workshop via steamcmd
abstract class IWorkshopPublishService {
  /// Stream of upload progress (0.0 to 1.0)
  Stream<double> get progressStream;

  /// Stream of raw steamcmd output lines
  Stream<String> get outputStream;

  /// Publish or update a Workshop item
  ///
  /// Returns [WorkshopPublishResult] on success.
  /// Throws [SteamGuardRequiredException] if Steam Guard code is needed.
  Future<Result<WorkshopPublishResult, SteamServiceException>> publish({
    required WorkshopPublishParams params,
    required String username,
    required String password,
    String? steamGuardCode,
  });

  /// Cancel the current publish operation
  Future<void> cancel();

  /// Check if steamcmd is available for publishing
  Future<bool> isAvailable();
}
