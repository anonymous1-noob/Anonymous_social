import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FeedPostPage extends StatefulWidget {
  const FeedPostPage({super.key});

  @override
  State<FeedPostPage> createState() => _FeedPostPageState();
}

class _FeedPostPageState extends State<FeedPostPage> {
  final SupabaseClient client = Supabase.instance.client;
  final TextEditingController _postController = TextEditingController();
  bool loading = false;

  Future<void> createPost() async {
    final content = _postController.text.trim();
    if (content.isEmpty) return;

    setState(() => loading = true);
    await client.from('posts').insert({
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'likes': 0,
      'comments': [],
    });
    setState(() {
      _postController.clear();
      loading = false;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Post created successfully!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Post')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _postController,
              decoration: const InputDecoration(
                hintText: 'Write your post...',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: loading ? null : createPost,
              child: loading
                  ? const CircularProgressIndicator()
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}
