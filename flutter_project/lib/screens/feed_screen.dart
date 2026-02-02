import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notifications_screen.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/report_dialog.dart';

class FeedScreen extends StatefulWidget {
  final int categoryId;

  FeedScreen({required this.categoryId});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final supabase = Supabase.instance.client;

  // Current user
  String? _currentUserId;
  StreamSubscription<AuthState>? _authSub;

  // Like cache for posts (optimistic feel)
  final Set<String> _likedPostIds = {};
  final Map<String, int> _postLikeCounts = {};

  bool _refreshing = false;
  bool _ensuredMyIdentity = false;

  // Identity cache
  final Map<String, Map<String, dynamic>> _identityByUser = {};
  bool _loadingIdentities = false;

  // Comment pagination/expand state
  final Set<String> _expandedParents = {};
  final Map<String, int> _visibleRepliesCountByParent = {};
  final Set<String> _expandedRepliesForParent = {};

  @override
  void initState() {
    super.initState();

    _currentUserId = supabase.auth.currentUser?.id;
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      setState(() => _currentUserId = user?.id);
      _fetchInitialLikes();
    });

    _fetchInitialLikes();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureMyAnonIdentity() async {
    if (_ensuredMyIdentity) return;
    final me = _currentUserId;
    if (me == null) return;

    _ensuredMyIdentity = true;
    try {
      await supabase.rpc('ensure_anon_identity', params: {'p_user_id': me});
    } catch (_) {
      // ignore
    }
  }

  // ✅ FIX: table name is post_likes (not posts_likes)
  Future<void> _fetchInitialLikes() async {
    final me = _currentUserId;
    if (me == null) return;

    try {
      final likes = await supabase.from('post_likes').select('post_id, user_id');

      final Set<String> liked = {};
      final Map<String, int> counts = {};

      for (final row in likes) {
        final pid = (row['post_id'] ?? '').toString();
        if (pid.isEmpty) continue;

        counts[pid] = (counts[pid] ?? 0) + 1;

        final uid = (row['user_id'] ?? '').toString();
        if (uid == me) liked.add(pid);
      }

      if (!mounted) return;
      setState(() {
        _likedPostIds
          ..clear()
          ..addAll(liked);

        _postLikeCounts
          ..clear()
          ..addAll(counts);
      });
    } catch (e, st) {
      debugPrint('FETCH LIKES ERROR: $e');
      debugPrint('$st');
    }
  }

  // ✅ FIX: table name is post_likes (not posts_likes)
  Future<void> _togglePostLike(String postId) async {
    final me = _currentUserId;
    if (me == null) return;

    final wasLiked = _likedPostIds.contains(postId);

    // Optimistic update
    setState(() {
      if (wasLiked) {
        _likedPostIds.remove(postId);
        final current = _postLikeCounts[postId] ?? 0;
        _postLikeCounts[postId] = (current - 1).clamp(0, 1 << 30);
      } else {
        _likedPostIds.add(postId);
        final current = _postLikeCounts[postId] ?? 0;
        _postLikeCounts[postId] = current + 1;
      }
    });

    try {
      if (wasLiked) {
        await supabase.from('post_likes').delete().match({
          'post_id': postId,
          'user_id': me,
        });
      } else {
        // Uses upsert so duplicate likes don't throw
        await supabase.from('post_likes').upsert(
          {'post_id': postId, 'user_id': me},
          onConflict: 'post_id,user_id',
        );
      }
    } catch (e, st) {
      debugPrint('LIKE TOGGLE ERROR: $e');
      debugPrint('$st');

      // Revert UI if backend failed
      if (!mounted) return;
      setState(() {
        if (wasLiked) {
          _likedPostIds.add(postId);
          final current = _postLikeCounts[postId] ?? 0;
          _postLikeCounts[postId] = current + 1;
        } else {
          _likedPostIds.remove(postId);
          final current = _postLikeCounts[postId] ?? 0;
          _postLikeCounts[postId] = (current - 1).clamp(0, 1 << 30);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Like failed: $e')),
      );
    }
  }

  Future<void> _loadIdentitiesForUsers(Set<String> userIds) async {
    if (_loadingIdentities) return;
    final missing = userIds.where((u) => !_identityByUser.containsKey(u)).toList();
    if (missing.isEmpty) return;

    _loadingIdentities = true;
    try {
      final res = await supabase
          .from('anon_identities')
          .select('user_id, display_name, avatar_color')
          .inFilter('user_id', missing);

      for (final row in res) {
        final uid = (row['user_id'] ?? '').toString();
        if (uid.isEmpty) continue;
        _identityByUser[uid] = Map<String, dynamic>.from(row as Map);
      }
      if (mounted) setState(() {});
    } catch (_) {
      // ignore
    } finally {
      _loadingIdentities = false;
    }
  }

  String _displayNameForUser(String userId) {
    final row = _identityByUser[userId];
    final name = (row?['display_name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return 'Anon';
  }

  Color _avatarColorForUser(String userId) {
    final row = _identityByUser[userId];
    final raw = row?['avatar_color'];
    if (raw is int) return Color(raw);
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return Color(parsed);
    }
    return const Color(0xFF94A3B8);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  String _timeAgo(dynamic createdAt) {
    try {
      if (createdAt == null) return '';
      final dt = DateTime.tryParse(createdAt.toString());
      if (dt == null) return '';
      final diff = DateTime.now().difference(dt.toLocal());

      if (diff.inSeconds < 60) return '${diff.inSeconds}s';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';
      final weeks = (diff.inDays / 7).floor();
      if (weeks < 5) return '${weeks}w';
      final months = (diff.inDays / 30).floor();
      if (months < 12) return '${months}mo';
      final years = (diff.inDays / 365).floor();
      return '${years}y';
    } catch (_) {
      return '';
    }
  }

  void _toggleRepliesExpanded(String parentCommentId) {
    setState(() {
      if (_expandedRepliesForParent.contains(parentCommentId)) {
        _expandedRepliesForParent.remove(parentCommentId);
      } else {
        _expandedRepliesForParent.add(parentCommentId);
        _visibleRepliesCountByParent[parentCommentId] ??= 3;
      }
    });
  }

  void _loadMoreReplies(String parentCommentId) {
    setState(() {
      final current = _visibleRepliesCountByParent[parentCommentId] ?? 3;
      _visibleRepliesCountByParent[parentCommentId] = current + 3;
    });
  }

  Future<void> _showPostMenu(Map<String, dynamic> post) async {
    final postId = (post['id'] ?? '').toString();
    final me = _currentUserId;
    final postUserId = (post['user_id'] ?? '').toString();
    final isMine = me != null && postUserId == me;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Report'),
                  onTap: () => Navigator.pop(ctx, 'report'),
                ),
                if (isMine) ...[
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Delete'),
                    onTap: () => Navigator.pop(ctx, 'delete'),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (action == null) return;

    if (action == 'delete') {
      try {
        await supabase.from('posts').update({'is_deleted': true}).eq('id', postId);
      } catch (_) {}
    } else if (action == 'report') {
      await showReportDialog(
        context: context,
        targetType: 'post',
        targetId: postId,
      );
    }
  }

  Widget _leftSidebar(BuildContext context, {required bool isWide}) {
    final width = isWide ? 280.0 : double.infinity;
    return Container(
      width: width,
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          const Text("Explore", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _sidebarItem(icon: Icons.people_outline, label: "Friends", onTap: () {}),
          _sidebarItem(icon: Icons.star_border, label: "Favourite", onTap: () {}),
          _sidebarItem(icon: Icons.category_outlined, label: "Categories", onTap: () {}),
          _sidebarItem(icon: Icons.bookmark_border, label: "Saved", onTap: () {}),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _sidebarItem(icon: Icons.settings_outlined, label: "Settings", onTap: () {}),
          const Spacer(),
          const Text("Tip: Tap ❤️ to like, 💬 to comment.",
              style: TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _sidebarItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.black87),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }

  Widget _captionText({
    required String username,
    required String caption,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    final full = '$username $caption';
    final shouldCollapse = full.length > 140;

    if (!shouldCollapse) {
      return RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black, height: 1.25),
          children: [
            TextSpan(text: username, style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: ' $caption'),
          ],
        ),
      );
    }

    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black, height: 1.25),
              children: [
                TextSpan(text: username, style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ' $caption'),
              ],
            ),
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: onToggle,
            child: const Text('less',
                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          ),
        ],
      );
    }

    final shortCaption = caption.length > 120 ? '${caption.substring(0, 120)}…' : caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black, height: 1.25),
            children: [
              TextSpan(text: username, style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: ' $shortCaption '),
              const TextSpan(
                text: 'more',
                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        InkWell(onTap: onToggle, child: const SizedBox(width: double.infinity, height: 1)),
      ],
    );
  }

  Widget _postCard({
    required Map<String, dynamic> post,
    required Map<String, int> commentCountByPost,
  }) {
    final postId = (post['id'] ?? '').toString();
    final authorId = (post['user_id'] ?? '').toString();
    final content = (post['content'] ?? '').toString();
    final editedAt = post['edited_at'];
    final createdAt = post['created_at'];

    final name = authorId.isNotEmpty ? _displayNameForUser(authorId) : 'Anon';
    final avatarColor =
        authorId.isNotEmpty ? _avatarColorForUser(authorId) : const Color(0xFF94A3B8);

    final isLiked = _likedPostIds.contains(postId);
    final likeCount = _postLikeCounts[postId] ?? 0;

    final commentCount = commentCountByPost[postId] ?? 0;

    bool expanded = false;
    bool showHeart = false;
    Timer? heartTimer;

    void triggerHeartBurst() {
      heartTimer?.cancel();
      setState(() => showHeart = true);
      heartTimer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() => showHeart = false);
      });
    }

    final time = _timeAgo(createdAt);

    return StatefulBuilder(
      builder: (context, setLocal) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w800)),
                              if (editedAt != null)
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Text("• Edited",
                                      style: TextStyle(fontSize: 12, color: Colors.black45)),
                                ),
                            ],
                          ),
                          if (time.isNotEmpty)
                            Text(time,
                                style: const TextStyle(fontSize: 12, color: Colors.black45)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz),
                      splashRadius: 18,
                      onPressed: () => _showPostMenu(post),
                    ),
                  ],
                ),
              ),

              Builder(
                builder: (_) {
                  final mediaUrl = (post['media_url'] ?? '').toString().trim();
                  if (mediaUrl.isEmpty) return const SizedBox.shrink();

                  return GestureDetector(
                    onDoubleTap: () {
                      if (!isLiked) {
                        _togglePostLike(postId);
                      }
                      triggerHeartBurst();
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: Image.network(
                            mediaUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: const Color(0xFFF3F4F6),
                                alignment: Alignment.center,
                                child: const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stack) {
                              return Container(
                                color: const Color(0xFFF3F4F6),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 56,
                                  color: Colors.black.withOpacity(0.18),
                                ),
                              );
                            },
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: showHeart ? 1 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: AnimatedScale(
                            scale: showHeart ? 1.0 : 0.85,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutBack,
                            child: const Icon(
                              Icons.favorite,
                              color: Colors.white,
                              size: 96,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 14)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                child: Row(
                  children: [
                    IconButton(
                      splashRadius: 20,
                      onPressed: () => _togglePostLike(postId),
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.redAccent : Colors.black87,
                      ),
                    ),
                    IconButton(
                      splashRadius: 20,
                      onPressed: () {
                        showCommentsSheet(
                          context: context,
                          postId: postId,
                          categoryId: widget.categoryId,
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                    ),
                    IconButton(
                      splashRadius: 20,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Share coming soon')),
                        );
                      },
                      icon: const Icon(Icons.send_outlined),
                    ),
                    const Spacer(),
                    IconButton(
                      splashRadius: 20,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Save coming soon')),
                        );
                      },
                      icon: const Icon(Icons.bookmark_border),
                    ),
                  ],
                ),
              ),

              if (likeCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 2),
                  child: Text('$likeCount likes',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),

              if (content.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: GestureDetector(
                    onTap: () => setLocal(() => expanded = !expanded),
                    child: _captionText(
                      username: name,
                      caption: content,
                      expanded: expanded,
                      onToggle: () => setLocal(() => expanded = !expanded),
                    ),
                  ),
                ),
              ],

              if (commentCount > 0) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: InkWell(
                    onTap: () {
                      showCommentsSheet(
                        context: context,
                        postId: postId,
                        categoryId: widget.categoryId,
                      );
                    },
                    child: Text(
                      'View all $commentCount comments',
                      style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureMyAnonIdentity();

    final postsStream = supabase.from('posts').stream(primaryKey: ['id']);
    final commentsStream = supabase.from('comments').stream(primaryKey: ['id']);
    final commentLikesStream = supabase.from('comment_likes').stream(primaryKey: ['id']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final bool showSidebar = false;

        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: const Text("Anonymous"),
            centerTitle: !isWide,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => NotificationsScreen()),
                  );
                },
              ),
            ],
          ),
          drawer: (!showSidebar || isWide)
              ? null
              : Drawer(child: _leftSidebar(context, isWide: false)),
          body: Row(
            children: [
              if (showSidebar && isWide) _leftSidebar(context, isWide: true),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _refreshing = true);
                    await Future.delayed(const Duration(milliseconds: 350));
                    await _fetchInitialLikes();
                    if (mounted) setState(() => _refreshing = false);
                  },
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: commentsStream,
                    builder: (context, commentsSnap) {
                      final allCommentsRaw = commentsSnap.data ?? [];

                      final Map<String, int> commentCountByPost = {};
                      final Set<String> commentUserIds = {};

                      for (final c in allCommentsRaw) {
                        if (c['is_deleted'] == true) continue;

                        final postId = (c['post_id'] ?? '').toString();
                        if (postId.isEmpty) continue;

                        final uid = (c['user_id'] ?? '').toString();
                        if (uid.isNotEmpty) commentUserIds.add(uid);

                        final parentId = (c['parent_comment_id'] ?? '').toString();
                        final isTopLevel = parentId.isEmpty || parentId == 'null';
                        if (isTopLevel) {
                          commentCountByPost[postId] = (commentCountByPost[postId] ?? 0) + 1;
                        }
                      }

                      _loadIdentitiesForUsers(commentUserIds);

                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: postsStream,
                        builder: (context, postsSnap) {
                          if (postsSnap.connectionState == ConnectionState.waiting && !postsSnap.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (postsSnap.hasError) {
                            return Center(
                              child: Text(
                                'Error loading posts:\n${postsSnap.error}',
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }

                          final posts = (postsSnap.data ?? [])
                              .where((p) => (p['is_deleted'] == false || p['is_deleted'] == null))
                              .where((p) {
                                if (widget.categoryId <= 0) return true;
                                return p['category_id'] == widget.categoryId;
                              })
                              .toList();

                          posts.sort((a, b) {
                            final aT = (a['created_at'] ?? '').toString();
                            final bT = (b['created_at'] ?? '').toString();
                            return bT.compareTo(aT);
                          });

                          if (posts.isEmpty) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              children: const [
                                SizedBox(height: 80),
                                Icon(Icons.hourglass_empty, size: 44, color: Colors.black38),
                                SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    "No posts yet",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                SizedBox(height: 6),
                                Center(
                                  child: Text(
                                    "Be the first to share something.",
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ),
                              ],
                            );
                          }

                          // Load like cache once per build tick is OK, but avoid loops:
                          // We already do it on init and refresh.

                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                itemCount: posts.length,
                                itemBuilder: (context, index) {
                                  final post = posts[index];

                                  final uid = (post['user_id'] ?? '').toString();
                                  if (uid.isNotEmpty) _loadIdentitiesForUsers({uid});

                                  return _postCard(
                                    post: post,
                                    commentCountByPost: commentCountByPost,
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
