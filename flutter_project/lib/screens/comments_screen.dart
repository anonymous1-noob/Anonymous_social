import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;

  const CommentsScreen({Key? key, required this.postId}) : super(key: key);

  @override
  _CommentsScreenState createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final client = Supabase.instance.client;
  final _commentController = TextEditingController();
  late Future<List<Comment>> _commentsFuture;
  late final StreamSubscription<List<Map<String, dynamic>>> _commentsSubscription;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _commentsFuture = _getComments();

    _commentsSubscription = client.from('comments').stream(primaryKey: ['id'])
      .listen((_) {
        if (mounted) {
          setState(() {
            _commentsFuture = _getComments();
          });
        }
      });
  }

  @override
  void dispose() {
    _commentsSubscription.cancel();
    super.dispose();
  }

  Future<List<Comment>> _getComments() async {
    final response = await client
        .from('comments')
        .select('*, users(display_name)')
        .eq('post_id', widget.postId)
        .order('created_at', ascending: false);

    return response.map((item) => _mapToComment(item)).toList();
  }

  Comment _mapToComment(Map<String, dynamic> item) {
    return Comment(
      id: item['id'],
      content: item['content'],
      author: item['users']?['display_name'] ?? 'Anonymous',
      createdAt: DateTime.parse(item['created_at']),
      likeCount: item['like_count'] ?? 0,
      isLiked: false, // Live like status is complex and best handled separately
    );
  }

  Future<void> _addComment() async {
    if (_commentController.text.isEmpty) return;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() { _loading = true; });

    try {
      await client.from('comments').insert({
        'post_id': widget.postId,
        'user_id': userId,
        'content': _commentController.text,
      });
      _commentController.clear();
    } on PostgrestException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() { _loading = false; });
      }
    }
  }

  Future<void> _toggleLike(Comment comment) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final currentLikes = await client.from('comment_likes').select().match({'comment_id': comment.id, 'user_id': userId});
    final isLiked = currentLikes.isNotEmpty;

    if (isLiked) {
      await client.from('comment_likes').delete().match({'comment_id': comment.id, 'user_id': userId});
    } else {
      await client.from('comment_likes').insert({'comment_id': comment.id, 'user_id': userId});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Comments')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Comment>>(
              future: _commentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (!snapshot.hasData || snapshot.data!.isEmpty) return Center(child: Text('No comments yet.'));

                final comments = snapshot.data!;
                return ListView.builder(
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return ListTile(
                      title: Text(comment.author),
                      subtitle: Text(comment.content),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () => _toggleLike(comment),
                            icon: Icon(Icons.favorite_border, color: Colors.grey),
                            label: Text(comment.likeCount.toString()),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _commentController, decoration: InputDecoration(hintText: 'Add a comment...'))),
                IconButton(icon: Icon(Icons.send), onPressed: _loading ? null : _addComment),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
