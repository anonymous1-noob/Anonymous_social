import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:anonymous_social/services/supabase_service.dart';

final commentsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>(
  (ref, String postId) {
    return supabase
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('post_id', postId)
        .map(
          (rows) => rows
              .where(
                (c) => c['is_deleted'] == false,
              )
              .toList(),
        );
  },
);