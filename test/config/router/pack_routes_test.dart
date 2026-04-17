import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/router/app_router.dart';

void main() {
  test('packCompilationEdit formats path correctly', () {
    expect(AppRoutes.packCompilationEdit('abc'), '/publishing/pack/abc/edit');
  });

  test('packCompilationNew is static constant', () {
    expect(AppRoutes.packCompilationNew, '/publishing/pack/new');
  });
}
