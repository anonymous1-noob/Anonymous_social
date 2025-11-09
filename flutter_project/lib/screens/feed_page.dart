import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'feed_post_page.dart'; // ✅ Make sure this import is here

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final SupabaseClient client = Supabase.instance.client;
  List<Map<String, dynamic>> posts = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchPosts();
  }

  /// ✅ Fetch all posts from Supabase
  Future<void> fetchPosts() async {
    setState(() => loading = true);
    final response = await client
        .from('posts')
        .select('id, content, like_count, comment_count, created_at')
        .order('created_at', ascending: false);
    setState(() {
      posts = List<Map<String, dynamic>>.from(response);
      loading = false;
    });
  }

  /// ✅ Like a post
  Future<void> likePost(String postId, int currentLikes) async {
    final user = client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to like posts')),
      );
      return;
    }

    try {
      // Check if user already liked
      final existingLike = await client
          .from('post_likes')
          .select()
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingLike != null) {
        // Unlike
        await client
            .from('post_likes')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', user.id);

        await client
            .from('posts')
            .update({'like_count': currentLikes - 1})
            .eq('id', postId);
      } else {
        // Like
        await client.from('post_likes').insert({
          'post_id': postId,
          'user_id': user.id,
        });

        await client
            .from('posts')
            .update({'like_count': currentLikes + 1})
            .eq('id', postId);
      }

      fetchPosts();
    } catch (e) {
      print('Error liking post: $e');
    }
  }

  /// ✅ Navigate to comments (you can expand this later)
  void openComments(String postId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Comments for post $postId coming soon...')),
    );
  }

  /// ✅ Refresh posts
  Future<void> refreshPosts() async {
    await fetchPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchPosts,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: refreshPosts,
              child: posts.isEmpty
                  ? const Center(child: Text('No posts yet'))
                  : ListView.builder(
                      itemCount: posts.length,
                      itemBuilder: (context, index) {
                        final post = posts[index];
                        return Card(
                          margin: const EdgeInsets.all(12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  post['content'] ?? '',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.thumb_up_alt_outlined),
                                          onPressed: () => likePost(
                                            post['id'].toString(),
                                            post['like_count'] ?? 0,
                                          ),
                                        ),
                                        Text('${post['like_count'] ?? 0}'),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.comment_outlined),
                                          onPressed: () => openComments(post['id']),
                                        ),
                                        Text('${post['comment_count'] ?? 0}'),
                                      ],
                                    ),
                                  ],
                                ),
                                Text(
                                  _formatTime(post['created_at']),
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const FeedPostPage()),
          ).then((_) => fetchPosts());
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatTime(String? dateString) {
    if (dateString == null) return '';
    final date = DateTime.tryParse(dateString);
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
