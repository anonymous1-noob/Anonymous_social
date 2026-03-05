import 'package:supabase_flutter/supabase_flutter.dart';

/// Saved posts service.
///
/// Recommended table:
/// saved_posts(user_id uuid, post_id text/uuid, created_at timestamptz)
/// with UNIQUE(user_id, post_id)
class SavedPostsService {
  SavedPostsService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static Future<Set<String>> fetchSavedPostIds() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return {};

    try {
      final res = await _client.from('saved_posts').select('post_id').eq('user_id', me);
      final rows = (res as List).cast<Map<String, dynamic>>();
      return rows.map((r) => (r['post_id'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();
    } on PostgrestException {
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> toggleSaved({required String postId, required bool shouldSave}) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw 'Not logged in';

    if (shouldSave) {
      await _client.from('saved_posts').upsert(
        {'user_id': me, 'post_id': postId},
        onConflict: 'user_id,post_id',
      );
    } else {
      await _client.from('saved_posts').delete().match({'user_id': me, 'post_id': postId});
    }
  }
}
