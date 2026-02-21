import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// A provider that fetches the list of all categories from the database.
// This is required for the multi-category selection UI.

// A reference to the Supabase client.
final _supabaseClientProvider = Provider((ref) => Supabase.instance.client);

final categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabaseClient = ref.watch(_supabaseClientProvider);

  try {
    final response = await supabaseClient
        .from('categories')
        .select('id, name')
        .order('name', ascending: true);
    return response;
  } catch (e) {
    print('Error fetching categories: $e');
    return [];
  }
});
