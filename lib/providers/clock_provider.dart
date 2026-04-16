import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ambient current-time provider. Widgets that render relative dates
/// (e.g., "2 months ago") should read this instead of calling DateTime.now()
/// so golden tests can pin an epoch.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
