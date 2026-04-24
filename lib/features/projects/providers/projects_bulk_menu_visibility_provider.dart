import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProjectsBulkMenuVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void show() => state = true;

  void hide() => state = false;
}

final projectsBulkMenuVisibilityProvider =
    NotifierProvider<ProjectsBulkMenuVisibilityNotifier, bool>(
  ProjectsBulkMenuVisibilityNotifier.new,
);
