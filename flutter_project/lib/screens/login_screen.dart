import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'register_screen.dart';
import 'feed_screen.dart';

/// The screen where users can sign in to the application.
///
/// This screen provides a simple email and password login form. Upon successful
/// authentication, it navigates the user to the main `FeedScreen`.
/// It also provides a button to navigate to the `RegisterScreen` for new users.
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // The Supabase client instance for all database and auth operations.
  final _client = Supabase.instance.client;
  
  // Controllers for the email and password text fields.
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // --- State Variables ---
  bool _loading = false; // Controls the visibility of the loading indicator.
  String? _error; // Holds any error message to be displayed to the user.

  /// Attempts to sign the user in using their email and password.
  Future<void> signInWithEmail() async {
    // Prevent multiple sign-in attempts while one is in progress.
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // After a successful login, navigate to the main feed.
      // The `mounted` check ensures the widget is still in the widget tree
      // before attempting a navigation, preventing errors if the user navigates away.
      if (res.user != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => FeedScreen()),
        );
      } else {
        // This case might occur if the sign-in response is unexpected.
        setState(() {
          _error = 'Login failed. Please check your credentials.';
        });
      }
    } on AuthException catch (e) {
      // Handle specific Supabase authentication errors (e.g., invalid password).
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      // Handle any other unexpected errors (e.g., network issues).
      setState(() {
        _error = 'An unexpected error occurred.';
      });
    } finally {
      // Always ensure the loading indicator is turned off, even if an error occurs.
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Always dispose of controllers to free up resources when the widget is removed.
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView( // Allows the view to be scrollable if content overflows.
          child: Column(
            children: [
              // --- Input Fields ---
              TextField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                obscureText: true, // Hides the password text.
              ),
              SizedBox(height: 20),
              
              // --- Action Buttons ---
              // Use a SizedBox to enforce a consistent width for the buttons.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : signInWithEmail, 
                  child: Text('Sign in'),
                ),
              ),
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _loading ? null : () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => RegisterScreen()));
                  }, 
                  child: Text('Create an account'),
                ),
              ),

              // --- Loading and Error Indicators ---
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: CircularProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
