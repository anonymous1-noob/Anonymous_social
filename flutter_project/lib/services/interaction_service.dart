import 'package:supabase_flutter/supabase_flutter.dart';

class InteractionService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<void> likePost(String postId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('user_post_interactions').insert({
      'user_id': user.id,
      'post_id': postId,
      'action': 'like',
    });

    await supabase.rpc('increment_like', params: {
      'p_post_id': postId,
    });
  }

  Future<void> trackView(String postId, int categoryId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('user_post_interactions').insert({
      'user_id': user.id,
      'post_id': postId,
      'action': 'view',
    });

    await supabase.rpc('update_user_interest', params: {
      'p_user_id': user.id,
      'p_category_id': categoryId,
    });
  }
}