import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'comments_screen.dart';
import 'create_post_screen.dart';

class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final client = Supabase.instance.client;
  late Future<List<Post>> _postsFuture;
  late final StreamSubscription<List<Map<String, dynamic>>> _postsSubscription;

  @override
  void initState() {
    super.initState();
    _postsFuture = _getPosts();

    _postsSubscription = client.from('posts').stream(primaryKey: ['id'])
      .listen((_) {
        if (mounted) {
          setState(() {
            _postsFuture = _getPosts();
          });
        }
      });
  }

  @override
  void dispose() {
    _postsSubscription.cancel();
    super.dispose();
  }

  Future<List<Post>> _getPosts() async {
    // The generic type argument which caused the build error has been removed.
    final response = await client
        .from('posts')
        .select('*, users(display_name)')
        .order('created_at', ascending: false);

    return response.map((item) => _mapToPost(item)).toList();
  }

  Post _mapToPost(Map<String, dynamic> item) {
    return Post(
      id: item['id'],
      content: item['content'],
      author: item['users']?['display_name'] ?? 'Anonymous',
      commentCount: item['comment_count'] ?? 0,
      likeCount: item['like_count'] ?? 0,
      isLiked: false, // Live like status is complex and best handled separately
    );
  }

  Future<void> _toggleLike(Post post) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final currentLikes = await client.from('post_likes').select().match({'post_id': post.id, 'user_id': userId});
    final isLiked = currentLikes.isNotEmpty;

    if (isLiked) {
      await client.from('post_likes').delete().match({'post_id': post.id, 'user_id': userId});
    } else {
      await client.from('post_likes').insert({'post_id': post.id, 'user_id': userId});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Feed')),
      body: FutureBuilder<List<Post>>(
        future: _postsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return Center(child: Text('No posts yet.'));

          final posts = snapshot.data!;
          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
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
                            icon: Icon(Icons.favorite_border, color: Colors.grey),
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
