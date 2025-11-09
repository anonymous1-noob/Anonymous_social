import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unnamedprojectv1/screens/feed_page.dart';

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

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    // Check if user already logged in (Supabase session)
    final session = client.auth.currentSession;
    if (session != null) {
      _navigateToFeed();
      return;
    }

    // Check for local guest login
    final prefs = await SharedPreferences.getInstance();
    final isGuest = prefs.getBool('guest_login') ?? false;
    if (isGuest) {
      _navigateToFeed();
    }

    // Listen to auth changes
    client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        _navigateToFeed();
      }
    });
  }

  Future<void> signInWithEmail() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = res.user;
      if (user == null) {
        setState(() => error = 'Unable to sign in');
      } else {
        _navigateToFeed();
      }
    } on AuthException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = 'Something went wrong');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> signUpWithEmail() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (res.user == null) {
        setState(() => error = 'Unable to register');
      } else {
        _navigateToFeed();
      }
    } on AuthException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = 'Something went wrong');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      await client.auth.signInWithOAuth(OAuthProvider.google);
    } catch (e) {
      setState(() => error = 'Google sign-in failed');
    }
  }

  Future<void> defaultLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('guest_login', true);
      _navigateToFeed();
    } catch (e) {
      setState(() => error = 'Guest login failed');
    }
  }

  void _navigateToFeed() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => FeedPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Welcome Back!",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: loading ? null : signInWithEmail,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Sign In'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: loading ? null : signUpWithEmail,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Register'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: loading ? null : signInWithGoogle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Sign In with Google'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: loading ? null : defaultLogin,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Default Login (Guest Mode)'),
              ),
              const SizedBox(height: 20),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(color: Colors.red),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
