import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected bottom-navigation tab of the main shell.
/// 0 Home · 1 Bookings · 2 Jobs (workers only) · last Profile.
final currentTabProvider = StateProvider<int>((ref) => 0);
