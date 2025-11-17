import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreatePostScreen extends StatefulWidget {
  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final client = Supabase.instance.client;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  bool _isAnonymous = false; // Restore the anonymous switch state

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await client.from('categories').select();
      setState(() {
        _categories = response;
        if (_categories.isNotEmpty) {
          _selectedCategoryId = _categories.first['id'] as int?;
        }
      });
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

  Future<void> _createPost() async {
    if (_contentController.text.isEmpty || _selectedCategoryId == null) return;

    setState(() { _loading = true; _error = null; });

    final authId = client.auth.currentUser?.id;
    if (authId == null) {
      setState(() {
        _error = 'You must be logged in to create a post.';
        _loading = false;
      });
      return;
    }

    try {
      // CORRECTED: Get the user's primary key from the users table
      final userResponse = await client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .single();
      
      final userId = userResponse['id'];

      // Use the correct user ID and anonymous value
      await client.from('posts').insert({
        'user_id': userId,
        'content': _contentController.text,
        'category_id': _selectedCategoryId,
        'anonymous': _isAnonymous, 
      });

      Navigator.of(context).pop();
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
              DropdownButtonFormField<int>(
                value: _selectedCategoryId,
                items: _categories.map((category) {
                  return DropdownMenuItem<int>(
                    value: category['id'] as int,
                    child: Text(category['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() { _selectedCategoryId = value; });
                },
                decoration: InputDecoration(labelText: 'Category'),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _contentController,
                decoration: InputDecoration(hintText: 'What\'s on your mind?'),
                maxLines: 5,
              ),
              SizedBox(height: 12),
              // Restore the anonymous switch UI
              SwitchListTile(
                title: Text('Post Anonymously'),
                value: _isAnonymous,
                onChanged: (value) {
                  setState(() { _isAnonymous = value; });
                },
              ),
              SizedBox(height: 20),
              ElevatedButton(onPressed: _loading ? null : _createPost, child: Text('Post')),
              if (_loading) Padding(padding: const EdgeInsets.only(top: 16.0), child: CircularProgressIndicator()),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_error!, style: TextStyle(color: Colors.red))),
            ],
          ),
        ),
      ),
    );
  }
}
