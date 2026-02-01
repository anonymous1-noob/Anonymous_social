import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://gvfpktjreztuwoxqiydk.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd2ZnBrdGpyZXp0dXdveHFpeWRrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMxNzAzOTgsImV4cCI6MjA3ODc0NjM5OH0.HUHoLTCzOJTa7YOgQnTHaMsm1XM_qUAE-oyvHqViIqk',
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthGate(),
    );
  }
}
