import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/scan_log_message.dart';
import 'package:twmt/providers/shared/service_providers.dart';

part 'mods_data_providers.g.dart';

/// Provider for the scan log stream from WorkshopScannerService
final scanLogStreamProvider = Provider<Stream<ScanLogMessage>>((ref) {
  final scannerService = ref.watch(workshopScannerServiceProvider);
  return scannerService.scanLogStream;
});

/// Tracks whether the mods screen has already forced its once-per-session
/// rescan. Stays alive for the whole app session so re-navigating to the
/// Mods screen does not retrigger a scan; resets only on app restart.
@Riverpod(keepAlive: true)
class ModsInitialRescanDone extends _$ModsInitialRescanDone {
  @override
  bool build() => false;

  void markDone() {
    state = true;
  }
}
