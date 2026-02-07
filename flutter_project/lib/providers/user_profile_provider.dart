import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A provider that exposes the Supabase client instance.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// A future provider that fetches the profile of the currently logged-in user.
///
/// It depends on the `supabaseClientProvider` to get the Supabase client.
/// It fetches all columns from the `users` table for the user whose `auth_id`
/// matches the current Supabase user's ID.
final userProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final supabaseClient = ref.watch(supabaseClientProvider);
  final user = supabaseClient.auth.currentUser;

  if (user == null) {
    return null; // No user logged in, so no profile to fetch.
  }

  try {
    // CORRECTED: The .select() method does not take a generic type.
    final response = await supabaseClient
        .from('users')
        .select('*') // Fetch all columns
        .eq('auth_id', user.id)
        .single();
    return response;
  } catch (e) {
    // Handle cases where the profile might not exist or other errors occur.
    return null;
  }
});
