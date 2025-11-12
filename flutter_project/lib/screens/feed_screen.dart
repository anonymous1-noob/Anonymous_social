import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'comments_screen.dart';
import 'create_post_screen.dart';
import 'edit_profile_screen.dart';

class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _client = Supabase.instance.client;
  late Future<List<Post>> _postsFuture;
  late final StreamSubscription<List<Map<String, dynamic>>> _postsSubscription;
  Map<String, bool> _likedPosts = {};

  @override
  void initState() {
    super.initState();
    _postsFuture = _getPosts();

    _postsSubscription = _client.from('posts').stream(primaryKey: ['id'])
      .listen((_) {
        if (mounted) {
          _refresh();
        }
      });
  }

  @override
  void dispose() {
    _postsSubscription.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _postsFuture = _getPosts();
    });
  }

  Future<List<Post>> _getPosts() async {
    // CORRECTED: Use a left join (the default) so posts with 0 likes are not excluded.
    final response = await _client
        .from('posts')
        .select('*, users(display_name), post_likes(user_id)')
        .order('created_at', ascending: false);

    _updateLikedStatus(response);
    return response.map((item) => _mapToPost(item)).toList();
  }

  void _updateLikedStatus(List<Map<String, dynamic>> data) {
    final authId = _client.auth.currentUser?.id;
    if (authId == null) return;

    final newLikedPosts = <String, bool>{};
    for (var item in data) {
      final likes = item['post_likes'] as List;
      newLikedPosts[item['id']] = likes.any((like) => like['user_id'] == authId);
    }
    setState(() {
      _likedPosts = newLikedPosts;
    });
  }

  Post _mapToPost(Map<String, dynamic> item) {
    return Post(
      id: item['id'],
      content: item['content'],
      author: item['anonymous'] ? 'Anonymous' : item['users']?['display_name'] ?? 'Anonymous',
      commentCount: item['comment_count'] ?? 0,
      likeCount: item['like_count'] ?? 0,
      isLiked: _likedPosts[item['id']] ?? false,
    );
  }

  Future<void> _toggleLike(Post post) async {
    await _client.rpc('toggle_post_like', params: {'post_id_input': post.id});
    // The realtime listener will trigger a refresh.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Feed'),
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen())),
          ),
        ],
      ),
      body: FutureBuilder<List<Post>>(
        future: _postsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('No posts yet.'));
          }

          final posts = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final isLiked = _likedPosts[post.id] ?? false;
                return Card(
                  margin: EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.author, style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text(post.content),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : Colors.grey),
                              label: Text(post.likeCount.toString()),
                              onPressed: () => _toggleLike(post),
                            ),
                            TextButton.icon(
                              icon: Icon(Icons.comment), 
                              label: Text(post.commentCount.toString()),
                              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommentsScreen(postId: post.id))),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreatePostScreen())),
        child: Icon(Icons.add),
      ),
    );
  }
}
