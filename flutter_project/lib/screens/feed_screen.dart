import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'comments_screen.dart';
import 'create_post_screen.dart';
import 'edit_profile_screen.dart';
import 'edit_post_screen.dart';

/// The main screen that displays the feed of posts.
///
/// This screen is the core of the user experience after logging in. It is responsible for:
/// - Fetching and displaying all posts in a scrollable list.
/// - Providing a dropdown menu to filter the posts by category.
/// - Allowing users to like posts, navigate to comments, and see post-impression counts.
/// - Granting users the ability to edit their own posts via a context menu.
/// - Handling data refreshes through pull-to-refresh and after returning from other screens.
/// - Safely initializing all necessary data (user ID, categories) before building the UI.
class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  // The standard Supabase client for all database and auth operations.
  final _client = Supabase.instance.client;
  
  // A single Future that controls the initial loading of the screen's essential data.
  // Using a single Future in this way is a robust pattern to prevent race conditions
  // and ensure all async setup is complete before the main UI is built.
  late final Future<void> _initFuture;
  
  // Realtime subscription to the 'posts' table. This automatically triggers a
  // refresh when any post is inserted, updated, or deleted in the database.
  StreamSubscription<List<Map<String, dynamic>>>? _postsSubscription;
  
  // --- State Variables ---
  List<Map<String, dynamic>> _categories = []; // Caches the list of categories for the filter dropdown.
  int? _selectedCategoryId; // The currently selected category ID for filtering. A `null` value means 'All Categories'.
  String? _currentUserId; // The primary key (UUID from `public.users`) of the currently logged-in user.
  Map<String, bool> _likedPosts = {}; // A map to track which posts the current user has liked for instant UI feedback.

  @override
  void initState() {
    super.initState();
    // Start the one-time, safe initialization process when the screen is first created.
    _initFuture = _initialize();
  }

  /// Performs the essential asynchronous setup for the screen.
  ///
  /// This function is called only once by `_initFuture`. It fetches:
  /// 1. The current user's primary key from the `users` table.
  /// 2. The list of all available categories.
  /// It also safely sets up the realtime listener after fetching is complete.
  Future<void> _initialize() async {
    // 1. Fetch the logged-in user's public profile ID (not the auth ID).
    final authId = _client.auth.currentUser?.id;
    if (authId != null) {
      try {
        final userResponse = await _client.from('users').select('id').eq('auth_id', authId).single();
        _currentUserId = userResponse['id'];
      } catch (e) {
        // This can happen if a user signs up but their profile insertion fails.
        // The app can continue, but they won't be able to see the 'Edit' button on their posts.
      }
    }

    // 2. Fetch the list of categories for the filter dropdown.
    try {
      final catResponse = await _client.from('categories').select('id, name');
      _categories = catResponse;
    } catch (e) {
      // If categories fail to load, the dropdown will simply be empty.
    }

    // 3. Set up the realtime listener for posts.
    _postsSubscription?.cancel(); // Always cancel any existing subscription first.
    _postsSubscription = _client.from('posts').stream(primaryKey: ['id']).listen((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    // Always cancel subscriptions in dispose() to prevent memory leaks.
    _postsSubscription?.cancel();
    super.dispose();
  }

  /// Triggers a rebuild of the widget, which causes the FutureBuilder in `_buildFeed`
  /// to re-run its future (`_getPosts`), thus refetching the latest data from the database.
  Future<void> _refresh() async {
    if (mounted) {
      setState(() {});
    }
  }

  /// Fetches the list of posts from the database.
  ///
  /// It applies the category filter if one is selected. It also fetches
  /// related user and like data to populate the UI.
  Future<List<Post>> _getPosts() async {
    var query = _client
        .from('posts')
        // Select all post columns, the author's display name, and the user_id of anyone who has liked the post.
        .select('*, user_id, users(display_name), post_likes(user_id)');

    // If a category is selected in the dropdown, apply it as a filter to the query.
    if (_selectedCategoryId != null) {
      query = query.eq('category_id', _selectedCategoryId!);
    }

    final response = await query.order('created_at', ascending: false);

    // After fetching, update the local map of which posts the current user has liked.
    _updateLikedStatus(response);
    return response.map((item) => _mapToPost(item)).toList();
  }

  /// Updates the `_likedPosts` map for instant UI feedback on likes.
  void _updateLikedStatus(List<Map<String, dynamic>> data) {
    if (_currentUserId == null) return;
    final newLikedPosts = <String, bool>{};
    for (var item in data) {
      final likes = item['post_likes'] as List;
      // For each post, check if the current user's ID exists within its list of likes.
      newLikedPosts[item['id']] = likes.any((like) => like['user_id'] == _currentUserId);
    }
    // This check is crucial. It prevents calling `setState` during the build process,
    // which would cause a crash. We only update the state if the widget is still mounted.
    if (mounted) {
      setState(() {
        _likedPosts = newLikedPosts;
      });
    }
  }

  /// Maps a raw database row (`Map<String, dynamic>`) to a structured `Post` object.
  Post _mapToPost(Map<String, dynamic> item) {
    return Post(
      id: item['id'],
      userId: item['user_id'],
      content: item['content'],
      author: item['anonymous'] ?? false ? 'Anonymous' : item['users']?['display_name'] ?? 'Anonymous',
      commentCount: item['comment_count'] ?? 0,
      likeCount: item['like_count'] ?? 0,
      impressionCount: item['impression_count'] ?? 0,
      isLiked: _likedPosts[item['id']] ?? false, // Use the pre-calculated like status.
    );
  }

  /// Calls the database RPC `toggle_post_like` to handle liking/unliking a post.
  Future<void> _toggleLike(Post post) async {
    // The RPC function handles all the complex database logic in a single, safe transaction.
    await _client.rpc('toggle_post_like', params: {'post_id_input': post.id});
    // Manually trigger a refresh to show the result instantly.
    _refresh();
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
              // Navigate to the profile screen and refresh the feed when the user returns.
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen()))
                .then((_) => _refresh());
            },
          ),
        ],
      ),
      // This FutureBuilder handles the initial, one-time setup of the screen.
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator()); // Show loading spinner during init.
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error initializing feed: ${snapshot.error}')); // Show error if init fails.
          }

          // Once initialization is successful, build the main, interactive feed UI.
          return _buildFeed();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to the create post screen and refresh the feed when the user returns.
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreatePostScreen()))
            .then((_) => _refresh());
        },
        child: Icon(Icons.add),
      ),
    );
  }

  /// Builds the main feed UI, which is only called after the `_initFuture` is complete.
  Widget _buildFeed() {
    return Column(
      children: [
        // --- Category Filter Dropdown ---
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: DropdownButtonFormField<int?>(
            value: _selectedCategoryId,
            decoration: InputDecoration(labelText: 'Filter by Category', border: OutlineInputBorder()),
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
                _refresh(); // Refresh the list of posts when the filter changes.
              });
            },
          ),
        ),
        // --- Post List ---
        Expanded(
          // This second FutureBuilder fetches and displays the posts each time `_refresh` is called.
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
                  // Show a helpful message if there are no posts.
                  child: Center(child: ListView(padding: const EdgeInsets.all(20), children: [Text('No posts in this category yet.')])), 
                );
              }

              final posts = postSnapshot.data!;
              // The main list of posts, with pull-to-refresh functionality.
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
                            // --- Post Header: Author and Edit Button ---
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(post.author, style: TextStyle(fontWeight: FontWeight.bold)),
                                // Only show the edit/delete menu if the current user is the post's author.
                                if (post.userId == _currentUserId)
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert),
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
                            // --- Post Content ---
                            Text(post.content),
                            SizedBox(height: 8),
                            // --- Post Actions: Like, Comment, Impressions ---
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
                                  onPressed: () {
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommentsScreen(postId: post.id)))
                                      .then((_) => _refresh());
                                  },
                                ),
                                Row(
                                  children: [
                                    Icon(Icons.remove_red_eye_outlined, color: Colors.grey, size: 18),
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
