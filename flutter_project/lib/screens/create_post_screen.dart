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
  bool _isAnonymous = false;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await client.from('categories').select();
      if (!mounted) return;
      setState(() {
        _categories = response;
        if (_categories.isNotEmpty) {
          _selectedCategoryId = _categories.first['id'] as int?;
        }
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to fetch categories.';
      });
    }
  }

  Future<void> _createPost() async {
    if (_contentController.text.isEmpty || _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields.')),
      );
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // Call the new, reliable RPC function that handles everything.
      await client.rpc('create_post_with_count_update', params: {
        'category_id_input': _selectedCategoryId,
        'content_input': _contentController.text,
        'anonymous_input': _isAnonymous,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; });
    } catch (e) {
      if (!mounted) return;
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
                    child: Text(category['name'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() { _selectedCategoryId = value; });
                },
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentController,
                decoration: const InputDecoration(hintText: 'What\'s on your mind?'),
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Post Anonymously'),
                value: _isAnonymous,
                onChanged: (value) {
                  setState(() { _isAnonymous = value; });
                },
                secondary: const Icon(Icons.visibility_off_outlined),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _loading ? null : _createPost, child: const Text('Post')),
              if (_loading) const Padding(padding: EdgeInsets.only(top: 16.0), child: CircularProgressIndicator()),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
    );
  }
}
