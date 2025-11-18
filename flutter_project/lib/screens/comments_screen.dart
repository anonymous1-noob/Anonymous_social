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
  // The realtime subscription is now a fallback, not the primary method for UI updates.
  late final StreamSubscription<List<Map<String, dynamic>>> _commentsSubscription;
  bool _loading = false;
  Map<String, bool> _likedComments = {};

  @override
  void initState() {
    super.initState();
    _commentsFuture = _getComments();

    _commentsSubscription = client.from('comments').stream(primaryKey: ['id'])
      .listen((_) {
        if (mounted) {
          _refresh();
        }
      });
  }

  @override
  void dispose() {
    _commentsSubscription.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _commentsFuture = _getComments();
      });
    }
  }

  Future<List<Comment>> _getComments() async {
    final response = await client
        .from('comments')
        .select('*, users(display_name), comment_likes(user_id)')
        .eq('post_id', widget.postId)
        .order('created_at', ascending: false);

    _updateLikedStatus(response);
    return response.map((item) => _mapToComment(item)).toList();
  }
  
  void _updateLikedStatus(List<Map<String, dynamic>> data) {
    final authId = client.auth.currentUser?.id;
    if (authId == null) return;

    final newLikedComments = <String, bool>{};
    for (var item in data) {
      final likes = item['comment_likes'] as List;
      newLikedComments[item['id']] = likes.any((like) => like['user_id'] == authId);
    }
    if (mounted) {
        setState(() {
            _likedComments = newLikedComments;
        });
    }
  }

  Comment _mapToComment(Map<String, dynamic> item) {
    return Comment(
      id: item['id'],
      content: item['content'],
      author: item['users']?['display_name'] ?? 'Anonymous',
      createdAt: DateTime.parse(item['created_at']),
      likeCount: item['like_count'] ?? 0,
      isLiked: _likedComments[item['id']] ?? false,
    );
  }

  Future<void> _addComment() async {
    if (_commentController.text.isEmpty) return;
    setState(() { _loading = true; });

    try {
      await client.rpc('add_post_comment', params: {
        'post_id_input': widget.postId,
        'content_input': _commentController.text,
      });
      _commentController.clear();
      _refresh(); // Manually trigger a refresh to update the UI instantly.
    } on PostgrestException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() { _loading = false; });
      }
    }
  }

  Future<void> _toggleLike(Comment comment) async {
    await client.rpc('toggle_comment_like', params: {'comment_id_input': comment.id});
    _refresh(); // Manually trigger a refresh to update the UI instantly.
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
                if (snapshot.connectionState == ConnectionState.waiting && _likedComments.isEmpty) {
                  return Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('No comments yet.'));
                }

                final comments = snapshot.data!;
                return ListView.builder(
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    final isLiked = _likedComments[comment.id] ?? false;
                    return ListTile(
                      title: Text(comment.author),
                      subtitle: Text(comment.content),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () => _toggleLike(comment),
                            icon: Icon(isLiked ? Icons.thumb_up : Icons.thumb_up_outlined, color: isLiked ? Theme.of(context).primaryColor : Colors.grey),
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
