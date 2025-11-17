import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

class EditPostScreen extends StatefulWidget {
  final Post post;

  const EditPostScreen({Key? key, required this.post}) : super(key: key);

  @override
  _EditPostScreenState createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  final _contentController = TextEditingController();
  final _client = Supabase.instance.client;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _contentController.text = widget.post.content;
  }

  Future<void> _updatePost() async {
    if (_contentController.text.isEmpty) return;

    setState(() { _loading = true; _error = null; });

    try {
      await _client
          .from('posts')
          .update({'content': _contentController.text})
          .eq('id', widget.post.id);

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
      appBar: AppBar(title: Text('Edit Post')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _contentController,
              decoration: InputDecoration(hintText: 'What\'s on your mind?'),
              maxLines: 5,
            ),
            SizedBox(height: 20),
            ElevatedButton(onPressed: _loading ? null : _updatePost, child: Text('Update Post')),
            if (_loading) Padding(padding: const EdgeInsets.only(top: 16.0), child: CircularProgressIndicator()),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_error!, style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
