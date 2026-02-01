import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';


final feedProvider = StreamProvider.family((ref, int categoryId) {
return supabase
.from('posts')
.stream(primaryKey: ['id'])
.eq('category_id', categoryId)
.eq('is_deleted', false)
.order('created_at', ascending: false);
});