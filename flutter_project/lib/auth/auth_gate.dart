import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/login_screen.dart';
import '../screens/home_shell.dart';
import '../screens/campus_onboarding_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<bool> _needsCampusSelection(SupabaseClient supabase) async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    try {
      // Batch 2+ supports selecting multiple campuses OR skipping campus.
      // We only gate the app until onboarding is completed once.
      final row = await supabase
          .from('users')
          .select('onboarding_done')
          .eq('auth_id', user.id)
          .maybeSingle();

      final done = row?['onboarding_done'];
      if (done is bool) return done == false;
      // If column exists but is null, treat as not done.
      if (done == null) return true;
      return false;
    } on PostgrestException {
      // If the column/table isn't present yet, don't block app launch.
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;

        if (session == null) {
          return LoginScreen();
        }

        return FutureBuilder<bool>(
          future: _needsCampusSelection(supabase),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final needsCampus = snap.data == true;
            if (needsCampus) {
              return const CampusOnboardingScreen();
            }

            // Default category = 0 means "All". User can pick a category from Explore.
            return const HomeShell(categoryId: 0);
          },
        );
      },
    );
  }
}
