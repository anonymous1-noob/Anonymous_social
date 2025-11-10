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
  // Changed to handle integer IDs from the database
  int? _selectedCategoryId;

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
          // Ensure the ID is treated as an int
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

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _error = 'You must be logged in to create a post.';
        _loading = false;
      });
      return;
    }

    try {
      await client.from('posts').insert({
        'user_id': userId,
        'content': _contentController.text,
        'category_id': _selectedCategoryId,
        'anonymous': false,
      });
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = 'An unexpected error occurred.'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Post')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Changed to handle integer values
            DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              items: _categories.map((category) {
                return DropdownMenuItem<int>(
                  // Ensure the value is an int
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
            SizedBox(height: 20),
            ElevatedButton(onPressed: _loading ? null : _createPost, child: Text('Post')),
            if (_loading) Padding(padding: const EdgeInsets.only(top: 16.0), child: CircularProgressIndicator()),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_error!, style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
