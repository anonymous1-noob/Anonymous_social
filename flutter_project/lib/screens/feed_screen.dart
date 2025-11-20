import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'comments_screen.dart';
import 'create_post_screen.dart';
import 'edit_profile_screen.dart';
import 'edit_post_screen.dart';

class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _client = Supabase.instance.client;
  late final Future<void> _initFuture;
  StreamSubscription<List<Map<String, dynamic>>>? _postsSubscription;
  
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  String? _currentUserId;
  Map<String, bool> _likedPosts = {};
  Map<String, bool> _dislikedPosts = {};

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    final authId = _client.auth.currentUser?.id;
    if (authId != null) {
      try {
        final userResponse = await _client.from('users').select('id').eq('auth_id', authId).single();
        _currentUserId = userResponse['id'];
      } catch (e) {}
    }

    try {
      final catResponse = await _client.from('categories').select('id, name');
      _categories = catResponse;
    } catch (e) {}

    _postsSubscription?.cancel();
    _postsSubscription = _client.from('posts').stream(primaryKey: ['id']).listen((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _postsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {});
    }
  }

  Future<List<Post>> _getPosts() async {
    var query = _client
        .from('posts')
        .select('*, user_id, users(display_name), post_likes(user_id), post_dislikes(user_id)');

    if (_selectedCategoryId != null) {
      query = query.eq('category_id', _selectedCategoryId!);
    }

    final response = await query.order('created_at', ascending: false);

    _updateReactionStatus(response);
    return response.map((item) => _mapToPost(item)).toList();
  }

  void _updateReactionStatus(List<Map<String, dynamic>> data) {
    if (_currentUserId == null) return;
    final newLikedPosts = <String, bool>{};
    final newDislikedPosts = <String, bool>{};
    for (var item in data) {
      final likes = (item['post_likes'] as List?) ?? [];
      final dislikes = (item['post_dislikes'] as List?) ?? [];
      
      newLikedPosts[item['id']] = likes.any((like) => like['user_id'] == _currentUserId);
      newDislikedPosts[item['id']] = dislikes.any((dislike) => dislike['user_id'] == _currentUserId);
    }
    
    _likedPosts = newLikedPosts;
    _dislikedPosts = newDislikedPosts;
  }

  Post _mapToPost(Map<String, dynamic> item) {
    return Post(
      id: item['id'],
      userId: item['user_id'],
      content: item['content'],
      author: item['anonymous'] ?? false ? 'Anonymous' : item['users']?['display_name'] ?? 'Anonymous',
      commentCount: item['comment_count'] ?? 0,
      likeCount: item['like_count'] ?? 0,
      dislikeCount: item['dislike_count'] ?? 0,
      impressionCount: item['impression_count'] ?? 0,
      isLiked: _likedPosts[item['id']] ?? false,
      isDisliked: _dislikedPosts[item['id']] ?? false,
    );
  }

  Future<void> _toggleLike(Post post) async {
    await _client.rpc('toggle_post_like', params: {'post_id_input': post.id});
    _refresh(); // RESTORED: This is required for instant UI updates.
  }

  Future<void> _toggleDislike(Post post) async {
    await _client.rpc('toggle_post_dislike', params: {'post_id_input': post.id});
    _refresh(); // RESTORED: This is required for instant UI updates.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Feed'),
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen()))
                .then((_) => _refresh());
            },
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error initializing feed: ${snapshot.error}'));
          }

          return _buildFeed();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreatePostScreen()))
            .then((_) => _refresh());
        },
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildFeed() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: DropdownButtonFormField<int?>(
            value: _selectedCategoryId,
            decoration: InputDecoration(labelText: 'Filter by Category'),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text('All Categories')),
              ..._categories.map((category) {
                return DropdownMenuItem<int?>(
                  value: category['id'] as int,
                  child: Text(category['name'] as String),
                );
              }),
            ],
            onChanged: (value) {
              setState(() {
                _selectedCategoryId = value;
                _refresh();
              });
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Post>>(
            future: _getPosts(),
            builder: (context, postSnapshot) {
              if (postSnapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (postSnapshot.hasError) {
                return Center(child: Text('Error loading posts: ${postSnapshot.error}'));
              }
              if (!postSnapshot.hasData || postSnapshot.data!.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: Center(child: ListView(children: [Text('No posts in this category yet.')]))
                );
              }

              final posts = postSnapshot.data!;
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    final isLiked = _likedPosts[post.id] ?? false;
                    final isDisliked = _dislikedPosts[post.id] ?? false;
                    return Card(
                      margin: EdgeInsets.all(8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(post.author, style: TextStyle(fontWeight: FontWeight.bold)),
                                if (post.userId == _currentUserId)
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditPostScreen(post: post)))
                                          .then((_) => _refresh());
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    ],
                                  ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(post.content),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    TextButton.icon(
                                      icon: Icon(isLiked ? Icons.thumb_up : Icons.thumb_up_outlined, color: isLiked ? Theme.of(context).primaryColor : Colors.grey),
                                      label: Text(post.likeCount.toString()),
                                      onPressed: () => _toggleLike(post),
                                    ),
                                    TextButton.icon(
                                      icon: Icon(isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined, color: isDisliked ? Theme.of(context).colorScheme.error : Colors.grey),
                                      label: Text(post.dislikeCount.toString()),
                                      onPressed: () => _toggleDislike(post),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  icon: Icon(Icons.comment), 
                                  label: Text(post.commentCount.toString()),
                                  onPressed: () {
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommentsScreen(postId: post.id)))
                                      .then((_) => _refresh());
                                  },
                                ),
                                Row(
                                  children: [
                                    Icon(Icons.remove_red_eye_outlined, color: Colors.grey),
                                    SizedBox(width: 4),
                                    Text(post.impressionCount.toString(), style: TextStyle(color: Colors.grey)),
                                  ],
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
        ),
      ],
    );
  }
}
