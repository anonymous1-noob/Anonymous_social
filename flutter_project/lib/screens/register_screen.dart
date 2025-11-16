import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A screen for new users to create an account.
///
/// This screen captures all necessary user details, including email, password,
/// username, display name, and an optional avatar URL. It also allows users to select
/// one or more categories to associate with their profile upon registration.
class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _client = Supabase.instance.client;

  // --- Text Field Controllers ---
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _avatarUrlController = TextEditingController();

  // --- State Variables ---
  List<Map<String, dynamic>> _categories = []; // Holds the list of all available categories.
  List<int> _selectedCategoryIds = []; // Holds the IDs of the categories the user has selected.
  bool _loading = false; // Controls the visibility of the loading indicator.
  String? _error; // Holds any error message to be displayed.

  @override
  void initState() {
    super.initState();
    // When the screen loads, fetch the list of categories to display.
    _fetchCategories();
  }

  @override
  void dispose() {
    // Always dispose of controllers to free up resources.
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  /// Fetches the list of all categories from the database.
  Future<void> _fetchCategories() async {
    try {
      final response = await _client.from('categories').select('id, name');
      if (mounted) {
        setState(() {
          _categories = response;
        });
      }
    } catch (e) {
      // If categories fail to load, the selection UI will just be empty.
    }
  }

  /// Handles the entire user registration process.
  Future<void> _signUp() async {
    if (_loading) return;

    // Basic validation
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();

    if (email.isEmpty || password.isEmpty || username.isEmpty || displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please fill all required fields.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // 1. Create the user in Supabase Auth.
      final res = await _client.auth.signUp(
        email: email,
        password: password,
      );
      final user = res.user;

      if (user != null) {
        // 2. Insert their profile into the public `users` table.
        await _client.from('users').insert({
          'auth_id': user.id,
          'username': username,
          'email': email,
          'display_name': displayName,
          'avatar_url': _avatarUrlController.text.trim(),
          'role': 'user',
          'status': 'active',
        });

        // Get the new user's primary key from the `users` table.
        final userProfileResponse = await _client.from('users').select('id').eq('auth_id', user.id).single();
        final userId = userProfileResponse['id'];

        // 3. Insert the selected categories into the `user_category` join table.
        if (_selectedCategoryIds.isNotEmpty) {
          final List<Map<String, dynamic>> userCategoryInserts = _selectedCategoryIds.map((categoryId) => {
            'user_id': userId,
            'category_id': categoryId,
          }).toList();
          await _client.from('user_category').insert(userCategoryInserts);
        }

        if (mounted) {
          // Show a success dialog and navigate back to the login screen.
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Success'),
                content: Text(res.session == null 
                    ? 'Registration complete! Please check your email to verify your account.' 
                    : 'Registration successful! You can now log in.'),
                actions: <Widget>[
                  TextButton(
                    child: Text('OK'),
                    onPressed: () {
                      Navigator.of(context).pop(); // Dismiss dialog
                      Navigator.of(context).pop(); // Go back to login screen
                    },
                  ),
                ],
              );
            },
          );
        }
      } else {
        setState(() {
          _error = 'Registration failed. Please try again.';
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = 'An unexpected error occurred: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Input Fields ---
              TextField(controller: _emailController, decoration: InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
              SizedBox(height: 12),
              TextField(controller: _passwordController, decoration: InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
              SizedBox(height: 12),
              TextField(controller: _usernameController, decoration: InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
              SizedBox(height: 12),
              TextField(controller: _displayNameController, decoration: InputDecoration(labelText: 'Display Name', border: OutlineInputBorder())),
              SizedBox(height: 12),
              TextField(controller: _avatarUrlController, decoration: InputDecoration(labelText: 'Avatar URL (optional)', border: OutlineInputBorder())),
              SizedBox(height: 20),
              
              // --- Category Selection ---
              Text('Select Your Categories', style: Theme.of(context).textTheme.headlineSmall),
              SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: _categories.map((category) {
                  final isSelected = _selectedCategoryIds.contains(category['id']);
                  return FilterChip(
                    label: Text(category['name'] as String),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCategoryIds.add(category['id'] as int);
                        } else {
                          _selectedCategoryIds.remove(category['id'] as int);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              SizedBox(height: 20),

              // --- Action Button and Indicators ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: _loading ? null : _signUp, child: Text('Register')),
              ),
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
