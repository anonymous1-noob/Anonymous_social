import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'comments_screen.dart';
import 'create_post_screen.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import '../widgets/post_popup.dart';

class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _client = Supabase.instance.client;
  late Future<List<Post>> _postsFuture;
  late final StreamSubscription<List<Map<String, dynamic>>> _postsSubscription;

  Map<String, bool> _likedPosts = {};
  Map<String, List<Map<String, dynamic>>> _postComments = {};
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _initFeed();
    _fetchProfile();

    _postsSubscription = _client
        .from('posts')
        .stream(primaryKey: ['id'])
        .listen((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _postsSubscription.cancel();
    super.dispose();
  }

  Future<void> _initFeed() async {
    final posts = await _getPosts();
    if (mounted) {
      setState(() {
        _postsFuture = Future.value(posts);
      });
    }
  }

  /// *******************************
  /// POPUP WINDOW FOR POST (MAIN FIX)
  /// *******************************
  void _openPostPopup(Post post) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
              horizontal: 100, vertical: 80),
          backgroundColor: Colors.grey.shade200,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: PostPopup(
            post: post,
            refreshParent: _refresh,
          ),
        );
      },
    );
  }

  Future<void> _fetchProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    final res =
        await _client.from('users').select().eq('id', uid).maybeSingle();

    if (mounted) setState(() => _profileData = res);
  }

  Future<void> _refresh() async {
    final posts = await _getPosts();
    if (mounted) setState(() => _postsFuture = Future.value(posts));
  }

  Future<List<Post>> _getPosts() async {
    final response = await _client
        .from('posts')
        .select('*, users(display_name), post_likes(user_id)')
        .order('created_at', ascending: false);

    _updateLikedStatus(response);

    await Future.wait(response.map((item) async {
      final postId = item['id'];
      final comments = await _client
          .from('comments')
          .select('content, users(display_name)')
          .eq('post_id', postId)
          .order('created_at', ascending: false)
          .limit(3);
      _postComments[postId] = comments;
    }));

    return response.map((item) => _mapToPost(item)).toList();
  }

  void _updateLikedStatus(List<Map<String, dynamic>> data) {
    final authId = _client.auth.currentUser?.id;
    if (authId == null) return;

    final newLikedPosts = <String, bool>{};

    for (var item in data) {
      final likes = item['post_likes'] as List;
      newLikedPosts[item['id']] =
          likes.any((like) => like['user_id'] == authId);
    }

    if (mounted) setState(() => _likedPosts = newLikedPosts);
  }

  Post _mapToPost(Map<String, dynamic> item) {
    return Post(
      id: item['id'],
      content: item['content'],
      author: item['anonymous']
          ? 'Anonymous'
          : item['users']?['display_name'] ?? 'Anonymous',
      commentCount: item['comment_count'] ?? 0,
      likeCount: item['like_count'] ?? 0,
      isLiked: _likedPosts[item['id']] ?? false,
    );
  }

  Future<void> _toggleLike(Post post) async {
    await _client.rpc('toggle_post_like',
        params: {'post_id_input': post.id});
    _refresh();
  }

  Future<void> _logout() async {
    await _client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.person_outline),
              onPressed: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                        builder: (_) => EditProfileScreen()))
                    .then((_) => _fetchProfile());
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
          ],
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(flex: 2, child: _buildLeftSection()),
            const SizedBox(width: 12),
            Expanded(flex: 6, child: _buildMiddleFeed()),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: _buildRightSection()),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context)
              .push(MaterialPageRoute(
                  builder: (_) => CreatePostScreen()))
              .then((_) => _refresh());
        },
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add),
      ),
    );
  }

  // LEFT PANEL
  Widget _buildLeftSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text("Categories",
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18)),
          SizedBox(height: 12),
          ListTile(leading: Icon(Icons.trending_up), title: Text("Trending")),
          ListTile(leading: Icon(Icons.group), title: Text("Community")),
          ListTile(leading: Icon(Icons.person), title: Text("My Posts")),
          ListTile(leading: Icon(Icons.bookmark), title: Text("Saved")),
        ],
      ),
    );
  }

  /// ********************************************
  /// MIDDLE FEED — UPDATED TO INCLUDE ONTAP POPUP
  /// ********************************************
  Widget _buildMiddleFeed() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: FutureBuilder<List<Post>>(
        future: _postsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _likedPosts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
                child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No posts yet"));
          }

          final posts = snapshot.data!;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final isLiked = _likedPosts[post.id] ?? false;

                return InkWell(
                  onTap: () => _openPostPopup(post),   // <<<<<< MAIN FIX
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.blueGrey),
                              const SizedBox(width: 10),
                              Text(post.author,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Text(post.content,
                              style: const TextStyle(
                                  fontSize: 15)),
                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                icon: Icon(
                                  isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isLiked
                                      ? Colors.red
                                      : Colors.grey[600],
                                ),
                                label: Text("${post.likeCount}"),
                                onPressed: () => _toggleLike(post),
                              ),
                              TextButton.icon(
                                icon: const Icon(
                                    Icons.comment_outlined),
                                label: Text(
                                    "${post.commentCount}"),
                                onPressed: () {
                                  Navigator.of(context)
                                      .push(MaterialPageRoute(
                                          builder: (_) =>
                                              CommentsScreen(
                                                  postId:
                                                      post.id)))
                                      .then((_) => _refresh());
                                },
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildRightSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text("Suggestions",
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18)),
          SizedBox(height: 12),
          Text("• Follow topics you love"),
          SizedBox(height: 8),
          Text("• Connect with others"),
          SizedBox(height: 8),
          Text("• Customize your feed"),
        ],
      ),
    );
  }
}
