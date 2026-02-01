import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';


final commentsProvider = StreamProvider.family((ref, String postId) {
return supabase
.from('comments')
.stream(primaryKey: ['id'])
.eq('post_id', postId)
.eq('is_deleted', false)
.order('created_at');
});