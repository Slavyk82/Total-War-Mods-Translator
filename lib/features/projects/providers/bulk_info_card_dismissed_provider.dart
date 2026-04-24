import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'projects_bulk_info_dismissed';

class BulkInfoCardDismissedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  Future<void> dismiss() async {
    state = const AsyncValue.data(true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  Future<void> reset() async {
    state = const AsyncValue.data(false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
  }
}

final bulkInfoCardDismissedProvider =
    AsyncNotifierProvider<BulkInfoCardDismissedNotifier, bool>(
      BulkInfoCardDismissedNotifier.new,
    );
