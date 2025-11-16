import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';

/// The main entry point for the application.
///
/// This function is responsible for setting up the necessary services before
/// running the app. It ensures that Flutter bindings are initialized, loads
/// environment variables from the `.env` file, and initializes the Supabase client.
Future<void> main() async {
  // Ensure that the Flutter widget binding is initialized before any async operations.
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from the `.env` file located in the project root.
  // This file contains sensitive information like Supabase URL and keys.
  await dotenv.load(fileName: '.env');

  // Initialize the Supabase client. This must be done before the app is run.
  // It uses the URL and anon key loaded from the environment variables.
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // Run the main application widget.
  runApp(const MyApp());
}

/// The root widget of the application.
///
/// This widget sets up the `MaterialApp` and defines the initial route (`home`).
/// In this case, it always starts with the `LoginScreen`, which handles the
/// initial authentication flow.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'anonymous_social', // The title of the application.
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // Example of customizing theme further
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 48), // Make buttons taller
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      // The `LoginScreen` is set as the initial screen of the app.
      home: LoginScreen(),
    );
  }
}
