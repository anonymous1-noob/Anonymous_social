import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A screen for creating a new post.
///
/// This screen allows a logged-in user to write content, select a category
/// from a dropdown, and choose whether to post anonymously using a switch.
class CreatePostScreen extends StatefulWidget {
  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final _client = Supabase.instance.client;

  // --- State Variables ---
  bool _loading = false; // Controls the loading indicator.
  String? _error; // Holds any error message to be displayed.
  List<Map<String, dynamic>> _categories = []; // List of available categories.
  int? _selectedCategoryId; // The ID of the currently selected category.
  bool _isAnonymous = false; // Whether the user has toggled the anonymous switch.

  @override
  void initState() {
    super.initState();
    // When the screen loads, fetch the list of categories for the dropdown.
    _fetchCategories();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  /// Fetches the list of all available categories from the database.
  Future<void> _fetchCategories() async {
    try {
      final response = await _client.from('categories').select('id, name');
      if (mounted) {
        setState(() {
          _categories = response;
          // Default to selecting the first category in the list.
          if (_categories.isNotEmpty) {
            _selectedCategoryId = _categories.first['id'] as int?;
          }
        });
      }
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch categories.';
      });
    }
  }

  /// Handles the creation of a new post.
  Future<void> _createPost() async {
    // Basic validation to ensure content is not empty and a category is selected.
    if (_contentController.text.isEmpty || _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please write something and select a category.')),
      );
      return;
    }

    setState(() { _loading = true; _error = null; });

    final authId = _client.auth.currentUser?.id;
    if (authId == null) {
      setState(() {
        _error = 'You must be logged in to create a post.';
        _loading = false;
      });
      return;
    }

    try {
      // Fetch the user's primary key (`id`) from the `users` table using their `auth_id`.
      final userResponse = await _client.from('users').select('id').eq('auth_id', authId).single();
      final userId = userResponse['id'];

      // Insert the new post into the `posts` table.
      await _client.from('posts').insert({
        'user_id': userId,
        'content': _contentController.text,
        'category_id': _selectedCategoryId,
        'anonymous': _isAnonymous,
      });

      // If successful, close the screen and return to the feed.
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = 'An unexpected error occurred.'; });
    } finally {
      if (mounted) {
        setState(() { _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Post')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // --- Category Dropdown ---
              DropdownButtonFormField<int?>(
                value: _selectedCategoryId,
                items: _categories.map((category) {
                  return DropdownMenuItem<int?>(
                    value: category['id'] as int,
                    child: Text(category['name'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() { _selectedCategoryId = value; });
                },
                decoration: InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              ),
              SizedBox(height: 12),
              
              // --- Content Text Field ---
              TextField(
                controller: _contentController,
                decoration: InputDecoration(
                  hintText: 'What\'s on your mind?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 8,
              ),
              SizedBox(height: 12),
              
              // --- Anonymous Switch ---
              SwitchListTile(
                title: Text('Post Anonymously'),
                value: _isAnonymous,
                onChanged: (value) {
                  setState(() { _isAnonymous = value; });
                },
                secondary: Icon(Icons.visibility_off_outlined),
              ),
              SizedBox(height: 20),
              
              // --- Action Button and Indicators ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: _loading ? null : _createPost, child: Text('Post')),
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
