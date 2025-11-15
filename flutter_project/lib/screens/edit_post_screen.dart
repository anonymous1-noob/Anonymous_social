import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

/// A screen for editing an existing post.
///
/// This screen is navigated to from the `FeedScreen` when a user chooses to edit
/// one of their own posts. It allows the user to modify the post's content.
class EditPostScreen extends StatefulWidget {
  final Post post;

  const EditPostScreen({Key? key, required this.post}) : super(key: key);

  @override
  _EditPostScreenState createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  final _contentController = TextEditingController();
  final _client = Supabase.instance.client;

  // --- State Variables ---
  bool _loading = false; // Controls the loading indicator.
  String? _error; // Holds any error message.

  @override
  void initState() {
    super.initState();
    // Pre-fill the text field with the post's existing content.
    _contentController.text = widget.post.content;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  /// Handles updating the post in the database.
  Future<void> _updatePost() async {
    // Basic validation
    if (_contentController.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Content cannot be empty.')),
      );
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // Perform the update operation on the `posts` table for the specific post ID.
      await _client
          .from('posts')
          .update({'content': _contentController.text})
          .eq('id', widget.post.id);

      // If successful, close the screen.
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
      appBar: AppBar(title: Text('Edit Post')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- Content Text Field ---
            TextField(
              controller: _contentController,
              decoration: InputDecoration(
                hintText: 'What\'s on your mind?',
                border: OutlineInputBorder(),
              ),
              maxLines: 8,
            ),
            SizedBox(height: 20),
            
            // --- Action Button and Indicators ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _loading ? null : _updatePost, child: Text('Update Post')),
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
    );
  }
}
