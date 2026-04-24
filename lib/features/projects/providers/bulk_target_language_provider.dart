import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'projects_bulk_target_lang';

class BulkTargetLanguageNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  Future<void> setLanguage(String? code) async {
    state = AsyncValue.data(code);
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, code);
    }
  }
}

final bulkTargetLanguageProvider =
    AsyncNotifierProvider<BulkTargetLanguageNotifier, String?>(
      BulkTargetLanguageNotifier.new,
    );
