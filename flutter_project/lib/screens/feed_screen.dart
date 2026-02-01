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

  String? _currentUserId;
  StreamSubscription<AuthState>? _authSub;

  // ---------- Inline Create Post ----------
  final TextEditingController _createPostController = TextEditingController();
  bool _posting = false;

  // ---------- Identity cache ----------
  final Map<String, Map<String, dynamic>> _identityByUser = {};
  bool _ensuredMyIdentity = false;
  bool _loadingIdentities = false;

  // ---------- Realtime likes state (posts) ----------
  RealtimeChannel? _likesChannel;
  final Map<String, int> _likeCountByPost = {};
  final Set<String> _likedByMe = {};
  bool _likesLoaded = false;

  // ---------- Feed inline comment expansion ----------
  final Map<String, int> _visibleCommentsCountByPost = {}; // postId -> visible count

  // ---------- Instagram-like per-post UI state ----------
  final Set<String> _expandedCaptions = {};
  final Set<String> _savedPosts = {};
  final Map<String, bool> _heartBurst = {};
  final Map<String, Timer> _heartTimers = {};
  final Map<String, TextEditingController> _commentCtrlByPost = {};
  final Map<String, bool> _sendingCommentByPost = {};

  // ---------- Nested replies preview inside feed ----------
  final Set<String> _expandedRepliesForParent = {}; // parentCommentId
  final Map<String, int> _visibleRepliesCountByParent = {}; // parentCommentId -> visible replies

  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = supabase.auth.currentSession?.user.id;

    _authSub = supabase.auth.onAuthStateChange.listen((event) {
      setState(() {
        _currentUserId = supabase.auth.currentSession?.user.id;

        _ensuredMyIdentity = false;
        _identityByUser.clear();

        _likeCountByPost.clear();
        _likedByMe.clear();
        _likesLoaded = false;

        _visibleCommentsCountByPost.clear();
        _commentCtrlByPost.values.forEach((c) => c.dispose());
        _commentCtrlByPost.clear();
        _sendingCommentByPost.clear();

        _expandedRepliesForParent.clear();
        _visibleRepliesCountByParent.clear();
      });

      _setupLikesRealtime();
    });

    _setupLikesRealtime();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _likesChannel?.unsubscribe();
    _createPostController.dispose();

    for (final t in _heartTimers.values) {
      t.cancel();
    }
    _heartTimers.clear();
    _commentCtrlByPost.values.forEach((c) => c.dispose());
    super.dispose();
  }

  // ===================== Identity helpers =====================
  Color _parseHexColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  Color _fallbackAvatarColor(String userId) {
    final hash = userId.hashCode.abs();
    const palette = [
      0xFFEF5350,
      0xFFAB47BC,
      0xFF5C6BC0,
      0xFF29B6F6,
      0xFF26A69A,
      0xFF9CCC65,
      0xFFFFCA28,
      0xFFFF7043,
    ];
    return Color(palette[hash % palette.length]);
  }

  String _fallbackAnonLabel(String userId) {
    final short = userId.replaceAll('-', '').toUpperCase();
    final tag = short.length >= 6 ? short.substring(0, 6) : short;
    return 'Anon #$tag';
  }

  String _initialsFromLabel(String label) {
    final letters = label.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (letters.length >= 2) return letters.substring(0, 2).toUpperCase();
    return 'AN';
  }

  Future<void> _ensureMyAnonIdentity() async {
    if (_ensuredMyIdentity) return;
    final me = _currentUserId;
    if (me == null) return;

    try {
      await supabase.rpc('get_my_anon_identity', params: {
        'category_id_input': widget.categoryId,
      });
    } catch (_) {}
    _ensuredMyIdentity = true;
  }

  Future<void> _loadIdentitiesForUsers(Set<String> userIds) async {
    if (_loadingIdentities) return;
    if (userIds.isEmpty) return;

    final missing = userIds.where((u) => !_identityByUser.containsKey(u)).toList();
    if (missing.isEmpty) return;

    _loadingIdentities = true;
    try {
      final rows = await supabase
          .from('user_anonymous_identity')
          .select('user_id, category_id, anon_name, color_hex, avatar_seed')
          .eq('category_id', widget.categoryId)
          .inFilter('user_id', missing);

      for (final r in rows) {
        final uid = (r['user_id'] ?? '').toString();
        if (uid.isNotEmpty) _identityByUser[uid] = Map<String, dynamic>.from(r);
      }

      if (mounted) setState(() {});
    } catch (_) {
      // ignore
    } finally {
      _loadingIdentities = false;
    }
  }

  String _displayNameForUser(String userId) {
    final identity = _identityByUser[userId];
    if (identity != null) {
      final name = (identity['anon_name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    return _fallbackAnonLabel(userId);
  }

  Color _displayColorForUser(String userId) {
    final identity = _identityByUser[userId];
    if (identity != null) {
      final hex = (identity['color_hex'] ?? '').toString().trim();
      if (hex.isNotEmpty) {
        try {
          return _parseHexColor(hex);
        } catch (_) {}
      }
    }
    return _fallbackAvatarColor(userId);
  }

  // ===================== Time helpers =====================
  String _timeAgo(dynamic createdAtValue) {
    if (createdAtValue == null) return '';
    try {
      final utc = DateTime.parse(createdAtValue.toString()).toUtc();
      final local = utc.toLocal();
      final diff = DateTime.now().difference(local);

      if (diff.inSeconds < 10) return 'now';
      if (diff.inSeconds < 60) return '${diff.inSeconds}s';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}d';

      return '${local.day.toString().padLeft(2, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.year}';
    } catch (_) {
      return '';
    }
  }

  bool _isEdited(Map<String, dynamic> row) {
    final created = row['created_at'];
    final updated = row['updated_at'];
    if (created == null || updated == null) return false;
    try {
      final c = DateTime.parse(created.toString()).toUtc();
      final u = DateTime.parse(updated.toString()).toUtc();
      return u.difference(c).inSeconds > 2;
    } catch (_) {
      return false;
    }
  }

  // ===================== Likes: fetch + realtime (posts) =====================
  Future<void> _fetchInitialLikes() async {
    try {
      final rows = await supabase.from('post_likes').select('id, post_id, user_id');

      _likeCountByPost.clear();
      _likedByMe.clear();

      final me = _currentUserId;
      for (final r in rows) {
        final pid = (r['post_id'] ?? '').toString();
        final uid = (r['user_id'] ?? '').toString();
        if (pid.isEmpty) continue;

        _likeCountByPost[pid] = (_likeCountByPost[pid] ?? 0) + 1;
        if (me != null && uid == me) _likedByMe.add(pid);
      }

      if (mounted) setState(() => _likesLoaded = true);
    } catch (_) {
      if (mounted) setState(() => _likesLoaded = true);
    }
  }

  void _applyLikeInsert(Map<String, dynamic> row) {
    final pid = (row['post_id'] ?? '').toString();
    final uid = (row['user_id'] ?? '').toString();
    if (pid.isEmpty) return;

    _likeCountByPost[pid] = (_likeCountByPost[pid] ?? 0) + 1;

    final me = _currentUserId;
    if (me != null && uid == me) _likedByMe.add(pid);
  }

  void _applyLikeDelete(Map<String, dynamic> oldRow) {
    final pid = (oldRow['post_id'] ?? '').toString();
    final uid = (oldRow['user_id'] ?? '').toString();
    if (pid.isEmpty) return;

    final current = _likeCountByPost[pid] ?? 0;
    final next = current - 1;
    _likeCountByPost[pid] = next < 0 ? 0 : next;

    final me = _currentUserId;
    if (me != null && uid == me) _likedByMe.remove(pid);
  }

  Future<void> _setupLikesRealtime() async {
    await _likesChannel?.unsubscribe();
    _likesChannel = null;

    await _fetchInitialLikes();

    final channel = supabase.channel('realtime:post_likes');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'post_likes',
      callback: (payload) {
        final newRow = payload.newRecord;
        if (newRow != null && mounted) {
          setState(() => _applyLikeInsert(Map<String, dynamic>.from(newRow)));
        }
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'post_likes',
      callback: (payload) {
        final oldRow = payload.oldRecord;
        if (oldRow != null && mounted) {
          setState(() => _applyLikeDelete(Map<String, dynamic>.from(oldRow)));
        } else {
          _fetchInitialLikes();
        }
      },
    );

    _likesChannel = channel;
    channel.subscribe();
  }

  void _needLoginSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please login to perform this action')),
    );
  }

  Future<void> _togglePostLike(String postId) async {
    final me = _currentUserId;
    if (me == null) {
      _needLoginSnack();
      return;
    }

    // optimistic update
    final wasLiked = _likedByMe.contains(postId);
    setState(() {
      if (wasLiked) {
        _likedByMe.remove(postId);
        _likeCountByPost[postId] = (_likeCountByPost[postId] ?? 0) - 1;
        if ((_likeCountByPost[postId] ?? 0) < 0) _likeCountByPost[postId] = 0;
      } else {
        _likedByMe.add(postId);
        _likeCountByPost[postId] = (_likeCountByPost[postId] ?? 0) + 1;
      }
    });

    try {
      await supabase.rpc('toggle_post_like', params: {
        'post_id_input': postId,
      });
    } catch (e) {
      // revert
      setState(() {
        if (wasLiked) {
          _likedByMe.add(postId);
          _likeCountByPost[postId] = (_likeCountByPost[postId] ?? 0) + 1;
        } else {
          _likedByMe.remove(postId);
          _likeCountByPost[postId] = (_likeCountByPost[postId] ?? 0) - 1;
          if ((_likeCountByPost[postId] ?? 0) < 0) _likeCountByPost[postId] = 0;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Like failed: $e')),
      );
    }
  }

  // ===================== Likes: inline (comments) =====================
  Future<void> _toggleCommentLike(String commentId) async {
    final me = _currentUserId;
    if (me == null) {
      _needLoginSnack();
      return;
    }

    try {
      await supabase.rpc('toggle_comment_like', params: {
        'comment_id_input': commentId,
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Comment like failed: $e')),
      );
    }
  }

  // ===================== Inline Create Post =====================
  Future<void> _createPost() async {
    final me = _currentUserId;
    if (me == null) {
      _needLoginSnack();
      return;
    }
    final text = _createPostController.text.trim();
    if (text.isEmpty) return;
    if (_posting) return;

    setState(() => _posting = true);
    try {
      await _ensureMyAnonIdentity();

      await supabase.from('posts').insert({
        'content': text,
        'user_id': me,
        'category_id': widget.categoryId,
        'is_deleted': false,
      });

      _createPostController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Posted ✅")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Post failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  // ===================== Inline comments in feed =====================
  TextEditingController _commentControllerForPost(String postId) {
    return _commentCtrlByPost.putIfAbsent(postId, () => TextEditingController());
  }

  Future<void> _addInlineComment(String postId) async {
    final me = _currentUserId;
    if (me == null) {
      _needLoginSnack();
      return;
    }

    final ctrl = _commentControllerForPost(postId);
    final text = ctrl.text.trim();
    if (text.isEmpty) return;

    if (_sendingCommentByPost[postId] == true) return;
    setState(() => _sendingCommentByPost[postId] = true);

    try {
      await _ensureMyAnonIdentity();

      await supabase.from('comments').insert({
        'post_id': postId,
        'user_id': me,
        'content': text,
        'is_deleted': false,
        'parent_comment_id': null,
      });

      ctrl.clear();

      setState(() {
        final current = _visibleCommentsCountByPost[postId] ?? 0;
        _visibleCommentsCountByPost[postId] = current == 0 ? 5 : current;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Comment failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _sendingCommentByPost[postId] = false);
    }
  }

  void _toggleCommentsOpen(String postId) {
    setState(() {
      final current = _visibleCommentsCountByPost[postId] ?? 0;
      if (current == 0) {
        _visibleCommentsCountByPost[postId] = 5;
      } else {
        _visibleCommentsCountByPost[postId] = 0; // collapse
      }
    });
  }

  void _loadMoreComments(String postId) {
    setState(() {
      final current = _visibleCommentsCountByPost[postId] ?? 0;
      _visibleCommentsCountByPost[postId] = current + 5;
    });
  }

  // ---------- replies preview toggles ----------
  void _toggleRepliesForParent(String parentCommentId) {
    setState(() {
      final expanded = _expandedRepliesForParent.contains(parentCommentId);
      if (expanded) {
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

  // ===================== Edit/Delete/Report Posts =====================
  Future<void> _showPostMenu(Map<String, dynamic> post) async {
    final postId = (post['id'] ?? '').toString();
    final authorId = (post['user_id'] ?? '').toString();
    final isMine = _currentUserId != null && authorId == _currentUserId;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMine)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text("Edit post"),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Delete post", style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            if (!isMine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text("Report"),
                onTap: () => Navigator.pop(context, 'report'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'edit') {
      await _editPostDialog(post);
    } else if (action == 'delete') {
      await _deletePostConfirm(postId);
    } else if (action == 'report') {
      await showReportDialog(
        context: context,
        targetType: 'post',
        targetId: postId,
      );
    }
  }

  Future<void> _editPostDialog(Map<String, dynamic> post) async {
    final postId = (post['id'] ?? '').toString();
    final initial = (post['content'] ?? '').toString();
    final controller = TextEditingController(text: initial);

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit post"),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(hintText: "Update your post..."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Save")),
        ],
      ),
    );

    if (saved != true) return;

    final newText = controller.text.trim();
    if (newText.isEmpty) return;

    try {
      await supabase.rpc('edit_post', params: {
        'post_id_input': postId,
        'content_input': newText,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Post updated ✅")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Edit failed: $e")));
    }
  }

  Future<void> _deletePostConfirm(String postId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete post?"),
        content: const Text("This will remove the post from feed (soft delete)."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await supabase.rpc('soft_delete_post', params: {
        'post_id_input': postId,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Post deleted ✅")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete failed: $e")));
    }
  }

  // ===================== Left sidebar =====================
  Widget _leftSidebar(BuildContext context, {required bool isWide}) {
    final items = [
      _SideItem(icon: Icons.people_alt_outlined, label: "Friends"),
      _SideItem(icon: Icons.star_border, label: "Favourites"),
      _SideItem(icon: Icons.category_outlined, label: "Categories"),
      _SideItem(icon: Icons.bookmark_border, label: "Saved"),
      _SideItem(icon: Icons.settings_outlined, label: "Settings"),
    ];

    return Container(
      width: isWide ? 280 : 220,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          const Text(
            "Menu",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final it in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(it.icon),
              title: Text(it.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("${it.label} (next)")),
                );
              },
            ),
          const Spacer(),
          const Text(
            "Next: categories will filter feed here.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ===================== Build =====================
  @override
  Widget build(BuildContext context) {
    _ensureMyAnonIdentity();

    final postsStream = supabase.from('posts').stream(primaryKey: ['id']);
    final commentsStream = supabase.from('comments').stream(primaryKey: ['id']);
    final commentLikesStream = supabase.from('comment_likes').stream(primaryKey: ['id']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

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
          drawer: isWide ? null : Drawer(child: _leftSidebar(context, isWide: false)),
          body: Row(
            children: [
              if (isWide) _leftSidebar(context, isWide: true),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _refreshing = true);
                    await Future.delayed(const Duration(milliseconds: 350));
                    await _fetchInitialLikes();
                    if (mounted) setState(() => _refreshing = false);
                  },
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: commentLikesStream,
                    builder: (context, likesSnap) {
                      final likes = likesSnap.data ?? [];
                      final me = _currentUserId;

                      final Map<String, int> likeCountByComment = {};
                      final Set<String> likedByMeComment = {};

                      for (final l in likes) {
                        final cid = (l['comment_id'] ?? '').toString();
                        if (cid.isEmpty) continue;
                        likeCountByComment[cid] = (likeCountByComment[cid] ?? 0) + 1;

                        final uid = (l['user_id'] ?? '').toString();
                        if (me != null && uid == me) likedByMeComment.add(cid);
                      }

                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: commentsStream,
                        builder: (context, commentsSnap) {
                          final allCommentsRaw = commentsSnap.data ?? [];

                          // For inline preview:
                          // - top-level comments per post (newest first)
                          // - replies per parent comment (newest first)
                          final Map<String, List<Map<String, dynamic>>> topLevelByPost = {};
                          final Map<String, List<Map<String, dynamic>>> repliesByParent = {};
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
                              topLevelByPost.putIfAbsent(postId, () => []).add(c);
                            } else {
                              repliesByParent.putIfAbsent(parentId, () => []).add(c);
                            }
                          }

                          for (final k in topLevelByPost.keys) {
                            topLevelByPost[k]!.sort((a, b) {
                              final aT = (a['created_at'] ?? '').toString();
                              final bT = (b['created_at'] ?? '').toString();
                              return bT.compareTo(aT);
                            });
                          }

                          for (final k in repliesByParent.keys) {
                            repliesByParent[k]!.sort((a, b) {
                              final aT = (a['created_at'] ?? '').toString();
                              final bT = (b['created_at'] ?? '').toString();
                              return bT.compareTo(aT);
                            });
                          }

                          return StreamBuilder<List<Map<String, dynamic>>>(
                            stream: postsStream,
                            builder: (context, postsSnap) {
                              if (postsSnap.connectionState == ConnectionState.waiting && !postsSnap.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              if (postsSnap.hasError) {
                                return Center(child: Text('Error loading posts:\n${postsSnap.error}'));
                              }

                              final allPosts = postsSnap.data ?? [];
                              final posts = allPosts
                                  .where((p) =>
                                      p['category_id'] == widget.categoryId &&
                                      (p['is_deleted'] == false || p['is_deleted'] == null))
                                  .toList()
                                ..sort((a, b) {
                                  final aT = (a['created_at'] ?? '').toString();
                                  final bT = (b['created_at'] ?? '').toString();
                                  return bT.compareTo(aT);
                                });

                              final authorIds = <String>{};
                              for (final p in posts) {
                                final uid = (p['user_id'] ?? '').toString();
                                if (uid.isNotEmpty) authorIds.add(uid);
                              }

                              _loadIdentitiesForUsers({...authorIds, ...commentUserIds});

                              if (!_likesLoaded) return const Center(child: CircularProgressIndicator());

                              final maxWidth = isWide ? 900.0 : double.infinity;

                              return ListView(
                                padding: EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: isWide ? 18 : 12,
                                ),
                                children: [
                                  Center(
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(maxWidth: maxWidth),
                                      child: _createPostBox(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  if (posts.isEmpty)
                                    Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: maxWidth),
                                        child: const Card(
                                          child: Padding(
                                            padding: EdgeInsets.all(18),
                                            child: Center(child: Text("No posts yet")),
                                          ),
                                        ),
                                      ),
                                    ),

                                  for (final post in posts)
                                    Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: maxWidth),
                                        child: _postCard(
                                          post,
                                          topLevelByPost[(post['id'] ?? '').toString()] ?? const [],
                                          repliesByParent,
                                          likeCountByComment,
                                          likedByMeComment,
                                        ),
                                      ),
                                    ),

                                  const SizedBox(height: 18),
                                ],
                              );
                            },
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

  // ===================== Create Post box UI =====================
  Widget _createPostBox() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Create post", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _createPostController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: "What's on your mind?",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _posting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton.icon(
                        onPressed: _createPost,
                        icon: const Icon(Icons.send),
                        label: const Text("Post"),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===================== Post card UI =====================
  
Widget _postCard(
    Map<String, dynamic> post,
    List<Map<String, dynamic>> topLevelCommentsNewestFirst,
    Map<String, List<Map<String, dynamic>>> repliesByParent,
    Map<String, int> likeCountByComment,
    Set<String> likedByMeComment,
  ) {
    final postId = (post['id'] ?? '').toString();
    final content = (post['content'] ?? '').toString();
    final authorId = (post['user_id'] ?? '').toString();

    final name = authorId.isNotEmpty ? _displayNameForUser(authorId) : 'Anon';
    final color = authorId.isNotEmpty ? _displayColorForUser(authorId) : Colors.grey;
    final initials = _initialsFromLabel(name);

    final time = _timeAgo(post['created_at']);
    final edited = _isEdited(post);

    final likesCount = _likeCountByPost[postId] ?? 0;
    final isLiked = _likedByMe.contains(postId);

    // Total comments (top-level + replies)
    int totalComments = topLevelCommentsNewestFirst.length;
    for (final parent in topLevelCommentsNewestFirst) {
      final pid = (parent['id'] ?? '').toString();
      totalComments += (repliesByParent[pid]?.length ?? 0);
    }

    final isCaptionExpanded = _expandedCaptions.contains(postId);
    final isSaved = _savedPosts.contains(postId);
    final showHeart = _heartBurst[postId] == true;

    void triggerHeartBurst() {
      _heartTimers[postId]?.cancel();
      setState(() {
        _heartBurst[postId] = true;
      });
      _heartTimers[postId] = Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() {
          _heartBurst[postId] = false;
        });
      });
    }

    final bool needsMore = content.trim().length > 140;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color,
                  child: Text(
                    initials,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (edited)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text("• Edited", style: TextStyle(fontSize: 12, color: Colors.black45)),
                            ),
                        ],
                      ),
                      if (time.isNotEmpty)
                        Text(time, style: const TextStyle(fontSize: 12, color: Colors.black45)),
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

          // Media area (Instagram-like, 1:1)
          // If you add a `media_url` column to `posts`, this will render the image.
          // Otherwise it falls back to a placeholder.
          GestureDetector(
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
                  child: Builder(
                    builder: (_) {
                      final mediaUrl = (post['media_url'] ?? '').toString().trim();

                      if (mediaUrl.isEmpty) {
                        return Container(
                          color: const Color(0xFFF3F4F6),
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 64,
                              color: Colors.black.withOpacity(0.18),
                            ),
                          ),
                        );
                      }

                      return ClipRRect(
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
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Actions row
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Row(
              children: [
                IconButton(
                  splashRadius: 20,
                  onPressed: () {
                    _togglePostLike(postId);
                  },
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
                    // Share stub (future)
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
                    setState(() {
                      if (isSaved) {
                        _savedPosts.remove(postId);
                      } else {
                        _savedPosts.add(postId);
                      }
                    });
                  },
                  icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                ),
              ],
            ),
          ),

          // Meta: likes + caption + comments entry
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (likesCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Text(
                      "$likesCount like${likesCount == 1 ? '' : 's'}",
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),

                // Caption (username + text)
                if (content.trim().isNotEmpty)
                  Wrap(
                    children: [
                      Text(
                        "$name ",
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        isCaptionExpanded || !needsMore ? content : content.trim().substring(0, 140) + "… ",
                        style: const TextStyle(fontSize: 14, height: 1.25),
                      ),
                      if (needsMore)
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (isCaptionExpanded) {
                                _expandedCaptions.remove(postId);
                              } else {
                                _expandedCaptions.add(postId);
                              }
                            });
                          },
                          child: Text(
                            isCaptionExpanded ? "less" : "more",
                            style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),

                if (totalComments > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InkWell(
                      onTap: () {
                        showCommentsSheet(
                          context: context,
                          postId: postId,
                          categoryId: widget.categoryId,
                        );
                      },
                      child: Text(
                        "View all $totalComments comment${totalComments == 1 ? '' : 's'}",
                        style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCommentRowWithReplies(
    Map<String, dynamic> c,
    List<Map<String, dynamic>> repliesNewestFirst,
    Map<String, int> likeCountByComment,
    Set<String> likedByMeComment,
  ) {
    final commentId = (c['id'] ?? '').toString();
    final userId = (c['user_id'] ?? '').toString();

    final name = userId.isNotEmpty ? _displayNameForUser(userId) : 'Anon';
    final color = userId.isNotEmpty ? _displayColorForUser(userId) : Colors.grey;
    final initials = _initialsFromLabel(name);

    final content = (c['content'] ?? '').toString();
    final time = _timeAgo(c['created_at']);
    final edited = _isEdited(c);

    final liked = likedByMeComment.contains(commentId);
    final likeCount = likeCountByComment[commentId] ?? 0;

    final replyCount = repliesNewestFirst.length;
    final isRepliesOpen = _expandedRepliesForParent.contains(commentId);
    final visibleReplies = _visibleRepliesCountByParent[commentId] ?? 3;

    // Replies are already newest-first; show latest N, but in UI we show oldest->newest inside that slice
    final shownReplies = isRepliesOpen
        ? repliesNewestFirst.take(visibleReplies).toList().reversed.toList()
        : <Map<String, dynamic>>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          // comment row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color,
                child: Text(
                  initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9E9EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                if (edited)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Text("Edited", style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  ),
                              ],
                            ),
                          ),
                          if (time.isNotEmpty) Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(content),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          InkWell(
                            onTap: () => _toggleCommentLike(commentId),
                            child: Row(
                              children: [
                                Icon(
                                  liked ? Icons.favorite : Icons.favorite_border,
                                  size: 16,
                                  color: liked ? Colors.redAccent : Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  likeCount == 0 ? "Like" : "$likeCount",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: liked ? Colors.redAccent : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          InkWell(
                            onTap: () {
                              // Keep feed simple: Reply goes to full thread
                              showCommentsSheet(
                                context: context,
                                postId: (c['post_id'] ?? '').toString(),
                                categoryId: widget.categoryId,
                              );
                            },
                            child: const Text(
                              "Reply",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(width: 14),
                          if (replyCount > 0)
                            InkWell(
                              onTap: () => _toggleRepliesForParent(commentId),
                              child: Text(
                                isRepliesOpen ? "Hide replies" : "View replies ($replyCount)",
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Replies preview
          if (isRepliesOpen && replyCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in shownReplies) _miniReplyRow(r, likeCountByComment, likedByMeComment),

                  if (visibleReplies < replyCount)
                    TextButton(
                      onPressed: () => _loadMoreReplies(commentId),
                      child: const Text("Load more replies (+3)"),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniReplyRow(
    Map<String, dynamic> r,
    Map<String, int> likeCountByComment,
    Set<String> likedByMeComment,
  ) {
    final commentId = (r['id'] ?? '').toString();
    final userId = (r['user_id'] ?? '').toString();

    final name = userId.isNotEmpty ? _displayNameForUser(userId) : 'Anon';
    final color = userId.isNotEmpty ? _displayColorForUser(userId) : Colors.grey;
    final initials = _initialsFromLabel(name);

    final content = (r['content'] ?? '').toString();
    final time = _timeAgo(r['created_at']);

    final liked = likedByMeComment.contains(commentId);
    final likeCount = likeCountByComment[commentId] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color,
            child: Text(
              initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE9E9EF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      if (time.isNotEmpty) Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(content),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _toggleCommentLike(commentId),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                          size: 15,
                          color: liked ? Colors.redAccent : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          likeCount == 0 ? "Like" : "$likeCount",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: liked ? Colors.redAccent : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideItem {
  final IconData icon;
  final String label;
  _SideItem({required this.icon, required this.label});
}
