import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final client = Supabase.instance.client;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> signUpWithEmail() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text);
      final user = res.user;

      if (user != null) {
        // Insert profile into public.users table
        await client.from('users').insert({
          'auth_id': user.id, // Corrected: was 'id'
          'username': _usernameController.text.trim(),
          'email': _emailController.text.trim(),
          'display_name': _displayNameController.text.trim(),
          'role': 'user',
          'status': 'active',
        });

        setState(() { loading = false; });

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Success'),
                content: Text('Successfully registered.'),
                actions: <Widget>[
                  TextButton(
                    child: Text('OK'),
                    onPressed: () {
                      Navigator.of(context).pop(); // Dismiss dialog
                      Navigator.of(context).pop(); // Return to login screen
                    },
                  ),
                ],
              );
            },
          );
        }
      } else {
        // Handle case where email confirmation is required
        setState(() {
          loading = false;
        });

        if (mounted) {
           showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Registration Sent'),
                content: Text('Please check your email to complete registration.'),
                actions: <Widget>[
                  TextButton(
                    child: Text('OK'),
                    onPressed: () {
                      Navigator.of(context).pop(); // Dismiss dialog
                      Navigator.of(context).pop(); // Return to login screen
                    },
                  ),
                ],
              );
            },
          );
        }
      }
    } on AuthException catch (e) {
      setState(() {
        error = e.message;
        loading = false;
      });
    } catch (e) {
      setState(() {
        // Provide more detailed error information
        error = 'An unexpected error occurred: ${e.toString()}';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _emailController, decoration: InputDecoration(labelText: 'Email')),
              TextField(controller: _passwordController, decoration: InputDecoration(labelText: 'Password'), obscureText: true),
              TextField(controller: _usernameController, decoration: InputDecoration(labelText: 'Username')),
              TextField(controller: _displayNameController, decoration: InputDecoration(labelText: 'Display Name')),
              SizedBox(height: 12),
              ElevatedButton(onPressed: loading ? null : signUpWithEmail, child: Text('Register')),
              if (loading) Padding(padding: const EdgeInsets.only(top: 16.0), child: CircularProgressIndicator()),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(error!, style: TextStyle(color: Colors.red))),
            ],
          ),
        ),
      ),
    );
  }
}
