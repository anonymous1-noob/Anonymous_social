import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'register_screen.dart';
import 'feed_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final client = Supabase.instance.client;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> signInWithEmail() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text);
      final user = res.user;

      if (user != null) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => FeedScreen()));
        }
      } else {
        setState(() {
          error = 'Invalid credentials. Please try again.';
          loading = false;
        });
      }
    } on AuthException catch (e) {
      setState(() {
        error = e.message;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = 'An unexpected error occurred.';
        loading = false;
      });
    }
  }

  Future<void> signInWithGoogle() async {
    // Similar loading/error handling can be added here if needed
    await client.auth.signInWithOAuth(OAuthProvider.google);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _emailController, decoration: InputDecoration(labelText: 'Email')),
              TextField(controller: _passwordController, decoration: InputDecoration(labelText: 'Password'), obscureText: true),
              SizedBox(height: 12),
              ElevatedButton(onPressed: loading ? null : signInWithEmail, child: Text('Sign in')),
              ElevatedButton(onPressed: loading ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => RegisterScreen())), child: Text('Register')),
              SizedBox(height: 12),
              ElevatedButton(onPressed: loading ? null : signInWithGoogle, child: Text('Sign in with Google')),
              if (loading) Padding(padding: const EdgeInsets.only(top: 16.0), child: CircularProgressIndicator()),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(error!, style: TextStyle(color: Colors.red))),
            ],
          ),
        ),
      ),
    );
  }
}
