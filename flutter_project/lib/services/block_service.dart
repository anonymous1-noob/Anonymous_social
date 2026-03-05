import 'local_prefs.dart';

/// Local (device-only) block list.
///
/// Why local?
/// - Works without DB migrations.
/// - Prevents seeing someone again on this device/session.
///
/// You can later move this to Supabase (user_blocks table) and keep the API.
class BlockService {
  static const _kBlockedUserIds = 'blocked_user_ids_v1';

  static Future<Set<String>> getBlockedUserIds() async {
    final prefs = await LocalPrefs.instance();
    final list = prefs.getStringList(_kBlockedUserIds) ?? <String>[];
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  static Future<void> blockUser(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    final prefs = await LocalPrefs.instance();
    final current = (prefs.getStringList(_kBlockedUserIds) ?? <String>[]).toSet();
    current.add(id);
    await prefs.setStringList(_kBlockedUserIds, current.toList());
  }

  static Future<void> unblockUser(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    final prefs = await LocalPrefs.instance();
    final current = (prefs.getStringList(_kBlockedUserIds) ?? <String>[]).toSet();
    current.remove(id);
    await prefs.setStringList(_kBlockedUserIds, current.toList());
  }
}
