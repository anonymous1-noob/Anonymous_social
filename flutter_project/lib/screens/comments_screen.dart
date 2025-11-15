import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

/// A screen that displays the comments for a specific post.
///
/// This screen is responsible for:
/// - Fetching and displaying all comments for a given `postId`.
/// - Allowing users to add new comments to the post.
/// - Allowing users to like and unlike individual comments.
/// - Displaying comments in chronological order.
class CommentsScreen extends StatefulWidget {
  /// The unique ID of the post whose comments are to be displayed.
  final String postId;

  const CommentsScreen({Key? key, required this.postId}) : super(key: key);

  @override
  _CommentsScreenState createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  // The Supabase client instance for all database operations.
  final _client = Supabase.instance.client;
  // Controller for the text input field where users write new comments.
  final _commentController = TextEditingController();

  // The main Future that drives the UI, fetching the list of comments.
  late Future<List<Comment>> _commentsFuture;
  
  // Realtime subscription to the 'comments' table to listen for changes.
  late final StreamSubscription<List<Map<String, dynamic>>> _commentsSubscription;
  
  // --- State Variables ---
  bool _loading = false; // Controls the loading indicator for adding a comment.
  Map<String, bool> _likedComments = {}; // Tracks the like status of each comment for the current user.
  String? _currentUserId; // The primary key (UUID) of the currently logged-in user.

  @override
  void initState() {
    super.initState();
    // Start the process of fetching the user ID and then the comments.
    _commentsFuture = _initializeAndFetchComments();

    // Set up a realtime listener to automatically refresh the comments
    // whenever a change occurs in the 'comments' table for this post.
    _commentsSubscription = _client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('post_id', widget.postId) // Only listen to changes for this specific post
        .listen((_) {
          if (mounted) {
            _refresh();
          }
        });
  }

  @override
  void dispose() {
    // Always cancel subscriptions and dispose controllers to prevent memory leaks.
    _commentsSubscription.cancel();
    _commentController.dispose();
    super.dispose();
  }
  
  /// Helper function to chain async setup, ensuring user ID is fetched before comments.
  Future<List<Comment>> _initializeAndFetchComments() async {
    await _fetchCurrentUserId();
    return _getComments();
  }

  /// Fetches the primary key of the currently logged-in user from the `public.users` table.
  Future<void> _fetchCurrentUserId() async {
    final authId = _client.auth.currentUser?.id;
    if (authId != null) {
      try {
        final userResponse = await _client.from('users').select('id').eq('auth_id', authId).single();
        _currentUserId = userResponse['id'];
      } catch (e) {
        // Handle error, e.g., if user profile is not found.
      }
    }
  }

  /// Triggers a rebuild of the FutureBuilder to refetch the comments.
  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        // By re-assigning the future, the FutureBuilder will re-run it.
        _commentsFuture = _getComments();
      });
    }
  }

  /// Fetches all comments for the current post from the database.
  Future<List<Comment>> _getComments() async {
    final response = await _client
        .from('comments')
        .select('*, users(display_name), comment_likes(user_id)')
        .eq('post_id', widget.postId)
        .order('created_at', ascending: true); // Show oldest comments first

    // After fetching, update the local state of which comments are liked.
    _updateLikedStatus(response);
    return response.map((item) => _mapToComment(item)).toList();
  }
  
  /// Updates the local `_likedComments` map for instant UI feedback.
  void _updateLikedStatus(List<Map<String, dynamic>> data) {
    if (_currentUserId == null) return;
    final newLikedComments = <String, bool>{};
    for (var item in data) {
      final likes = item['comment_likes'] as List;
      // For each comment, check if the current user's ID is in its list of likes.
      newLikedComments[item['id']] = likes.any((like) => like['user_id'] == _currentUserId);
    }
    if (mounted) {
      setState(() {
        _likedComments = newLikedComments;
      });
    }
  }

  /// Maps a raw database row to a structured `Comment` object.
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

  /// Calls the database RPC to add a new comment to the current post.
  Future<void> _addComment() async {
    if (_commentController.text.isEmpty) return;
    setState(() { _loading = true; });

    try {
      // Use the dedicated RPC function for atomicity and correctness.
      await _client.rpc('add_post_comment', params: {
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

  /// Calls the database RPC to toggle a like on a specific comment.
  Future<void> _toggleLike(Comment comment) async {
    await _client.rpc('toggle_comment_like', params: {'comment_id_input': comment.id});
    _refresh(); // Manually trigger a refresh to update the UI instantly.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Comments')),
      body: Column(
        children: [
          // --- Comment List ---
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
                      title: Text(comment.author, style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(comment.content),
                      trailing: TextButton.icon(
                        onPressed: () => _toggleLike(comment),
                        icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : Colors.grey, size: 20),
                        label: Text(comment.likeCount.toString()),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // --- Add Comment Input Area ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(hintText: 'Add a comment...', border: OutlineInputBorder()),
                  )
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _loading ? null : _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
