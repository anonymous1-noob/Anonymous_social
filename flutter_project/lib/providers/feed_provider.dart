import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 

import 'user_profile_provider.dart';

/// A provider that fetches the feed for a given category using a simple, robust query.
final feedProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((ref, int categoryId) async {
  final supabaseClient = ref.watch(supabaseClientProvider);

  try {
    final postCategoryResponse = await supabaseClient
        .from('post_categories')
        .select('post_id')
        .eq('category_id', categoryId);

    final postIds = postCategoryResponse.map((row) => row['post_id'] as String).toList();

    if (postIds.isEmpty) {
      return [];
    }

    // CORRECTED: The query now also fetches the author's display_name.
    final postsResponse = await supabaseClient
        .from('posts')
        .select('*, users(display_name)') // Join with users table
        .in_('id', postIds)
        .order('created_at', ascending: false);

    return postsResponse;

  } catch (e) {
    print('Error fetching feed: $e');
    return [];
  }
});
