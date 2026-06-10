// Regression test for the 2026-06-09 review finding L9: the "Default"
// RPFM schema path button must derive the roaming-profile directory from
// %APPDATA% (falling back to %USERPROFILE%\AppData\Roaming) instead of
// hardcoding C:\Users\<USERNAME>, which is wrong on relocated profiles,
// profile folders whose name differs from the account name, and systems
// where Windows is not installed on C:.
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/widgets/general/rpfm_section.dart';

void main() {
  group('resolveDefaultRpfmSchemaPath', () {
    const suffix = r'\FrodoWazEre\rpfm\config\schemas';

    test('uses APPDATA when set', () {
      final result = resolveDefaultRpfmSchemaPath({
        'APPDATA': r'C:\Users\jmp\AppData\Roaming',
      });
      expect(result, r'C:\Users\jmp\AppData\Roaming' + suffix);
    });

    test('honours non-C: drives and profile folders that differ from the '
        'account name', () {
      final result = resolveDefaultRpfmSchemaPath({
        'APPDATA': r'D:\Profiles\johns\AppData\Roaming',
        'USERNAME': 'John Smith', // must be ignored
      });
      expect(result, r'D:\Profiles\johns\AppData\Roaming' + suffix);
    });

    test('prefers APPDATA over USERPROFILE', () {
      final result = resolveDefaultRpfmSchemaPath({
        'APPDATA': r'E:\Roaming',
        'USERPROFILE': r'C:\Users\jmp',
      });
      expect(result, r'E:\Roaming' + suffix);
    });

    test('falls back to USERPROFILE\\AppData\\Roaming when APPDATA is '
        'missing', () {
      final result = resolveDefaultRpfmSchemaPath({
        'USERPROFILE': r'D:\Users\jmp',
      });
      expect(result, r'D:\Users\jmp\AppData\Roaming' + suffix);
    });

    test('treats an empty APPDATA as absent', () {
      final result = resolveDefaultRpfmSchemaPath({
        'APPDATA': '',
        'USERPROFILE': r'C:\Users\jmp',
      });
      expect(result, r'C:\Users\jmp\AppData\Roaming' + suffix);
    });

    test('returns null when both APPDATA and USERPROFILE are unavailable',
        () {
      expect(resolveDefaultRpfmSchemaPath({}), isNull);
      expect(
        resolveDefaultRpfmSchemaPath({'APPDATA': '', 'USERPROFILE': ''}),
        isNull,
      );
      // USERNAME alone is no longer enough — it was the source of the bug.
      expect(
        resolveDefaultRpfmSchemaPath({'USERNAME': 'jmp'}),
        isNull,
      );
    });

    test('does not double the separator when APPDATA has a trailing '
        'backslash', () {
      final result = resolveDefaultRpfmSchemaPath({
        'APPDATA': 'C:\\Users\\jmp\\AppData\\Roaming\\',
      });
      expect(result, r'C:\Users\jmp\AppData\Roaming' + suffix);
    });
  });
}
