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
  Map<String, bool> _likedComments = {};

  @override
  void initState() {
    super.initState();
    _commentsFuture = _getComments();

    // Realtime subscription to refresh comments on any change
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
    setState(() {
      _commentsFuture = _getComments();
    });
  }

  Future<List<Comment>> _getComments() async {
    // Fetch comments and the liked status for the current user
    final response = await client
        .from('comments')
        .select('*, users(display_name), comment_likes!inner(user_id)')
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
      // Check if the current user's ID is in the list of likes
      newLikedComments[item['id']] = likes.any((like) => like['user_id'] == authId);
    }
    setState(() {
      _likedComments = newLikedComments;
    });
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
      // Call the RPC function
      await client.rpc('add_post_comment', params: {
        'post_id_input': widget.postId,
        'content_input': _commentController.text,
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
    // Call the RPC function
    await client.rpc('toggle_comment_like', params: {'comment_id_input': comment.id});
    // The realtime subscription will handle the refresh
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
                if (snapshot.connectionState == ConnectionState.waiting) {
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
                            icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : Colors.grey),
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
