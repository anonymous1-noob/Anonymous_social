import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreatePostScreen extends StatefulWidget {
  final int categoryId;

  const CreatePostScreen({super.key, required this.categoryId});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final supabase = Supabase.instance.client;

  final TextEditingController _controller = TextEditingController();
  bool _posting = false;
  String? _error;

  Future<void> _submit() async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) {
      setState(() => _error = 'Please login to post');
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write something first');
      return;
    }

    if (text.length > 600) {
      setState(() => _error = 'Post too long (max 600 characters)');
      return;
    }

    setState(() {
      _posting = true;
      _error = null;
    });

    try {
      // Ensure anonymous identity exists (non-blocking)
      try {
        await supabase.rpc('get_my_anon_identity', params: {
          'category_id_input': widget.categoryId,
        });
      } catch (_) {}

      await supabase.from('posts').insert({
        'user_id': me,
        'category_id': widget.categoryId,
        'content': text,
        'is_deleted': false,
      });

      if (!mounted) return;
      Navigator.pop(context, true); // success
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPost = _controller.text.trim().isNotEmpty && !_posting;

    return Scaffold(
      appBar: AppBar(
        title: const Text("New Post"),
        actions: [
          TextButton(
            onPressed: canPost ? _submit : null,
            child: _posting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Post"),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: const [
                    CircleAvatar(
                      radius: 18,
                      child: Icon(Icons.person, size: 18),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Posting as Anonymous",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  maxLines: 8,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: "What’s happening?",
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      "${_controller.text.trim().length}/600",
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Media upload coming next")),
                        );
                      },
                      icon: const Icon(Icons.image_outlined),
                    ),
                    IconButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Polls coming next")),
                        );
                      },
                      icon: const Icon(Icons.poll_outlined),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: canPost ? _submit : null,
                    child: _posting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text("Post"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
