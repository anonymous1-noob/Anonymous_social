import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/report_dialog.dart';

class CommentsScreen extends StatefulWidget {
  final String postId;
  final int categoryId;

  CommentsScreen({required this.postId, required this.categoryId});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final supabase = Supabase.instance.client;

  // Bottom composer for new top-level comments
  final TextEditingController _commentController = TextEditingController();
  bool _postingComment = false;

  // Inline reply composer (shown under selected parent comment)
  String? _replyToCommentId;
  String? _replyToUserId;
  final TextEditingController _replyController = TextEditingController();
  bool _postingReply = false;

  // Collapsible replies per parent
  final Set<String> _expandedParents = {};

  String? _currentUserId;
  StreamSubscription<AuthState>? _authSub;

  // Identity cache
  final Map<String, Map<String, dynamic>> _identityByUser = {};
  bool _ensuredMyIdentity = false;
  bool _loadingIdentities = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = supabase.auth.currentSession?.user.id;

    _authSub = supabase.auth.onAuthStateChange.listen((event) {
      setState(() {
        _currentUserId = supabase.auth.currentSession?.user.id;
        _ensuredMyIdentity = false;
        _identityByUser.clear();
        _expandedParents.clear();
        _replyToCommentId = null;
        _replyToUserId = null;
        _replyController.clear();
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _commentController.dispose();
    _replyController.dispose();
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
    } catch (_) {} finally {
      _ensuredMyIdentity = true;
    }
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

  // ===================== UI helpers =====================
  void _needLoginSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please login to perform this action')),
    );
  }

  // ===================== Actions =====================
  Future<void> _addTopLevelComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _postingComment) return;

    final userId = _currentUserId;
    if (userId == null) {
      _needLoginSnack();
      return;
    }

    setState(() => _postingComment = true);

    try {
      await _ensureMyAnonIdentity();

      await supabase.from('comments').insert({
        'post_id': widget.postId,
        'user_id': userId,
        'content': text,
        'is_deleted': false,
        'parent_comment_id': null,
      });

      _commentController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add comment: $e')),
      );
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  void _openInlineReply(String parentCommentId, String parentUserId) {
    final userId = _currentUserId;
    if (userId == null) {
      _needLoginSnack();
      return;
    }

    setState(() {
      _expandedParents.add(parentCommentId);
      _replyToCommentId = parentCommentId;
      _replyToUserId = parentUserId;
      _replyController.clear();
    });
  }

  void _cancelInlineReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToUserId = null;
      _replyController.clear();
    });
  }

  Future<void> _postInlineReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _postingReply) return;

    final userId = _currentUserId;
    if (userId == null) {
      _needLoginSnack();
      return;
    }

    final parentId = _replyToCommentId;
    if (parentId == null) return;

    setState(() => _postingReply = true);

    try {
      await _ensureMyAnonIdentity();

      await supabase.from('comments').insert({
        'post_id': widget.postId,
        'user_id': userId,
        'content': text,
        'is_deleted': false,
        'parent_comment_id': parentId,
      });

      _cancelInlineReply();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reply failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _postingReply = false);
    }
  }

  Future<void> _toggleLike(String commentId) async {
    final userId = _currentUserId;
    if (userId == null) {
      _needLoginSnack();
      return;
    }

    try {
      await supabase.rpc('toggle_comment_like', params: {
        'comment_id_input': commentId,
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Like failed: $e')),
      );
    }
  }

  // ===================== Menu: Edit/Delete/Report =====================
  Future<void> _showCommentMenu(Map<String, dynamic> row) async {
    final commentId = (row['id'] ?? '').toString();
    final authorId = (row['user_id'] ?? '').toString();
    final isMine = _currentUserId != null && authorId == _currentUserId;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text("Report"),
                onTap: () => Navigator.pop(context, 'report'),
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text("Edit"),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Delete", style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'report') {
      await showReportDialog(
        context: context,
        targetType: 'comment',
        targetId: commentId,
      );
      return;
    }

    if (action == 'edit') {
      await _editCommentDialog(commentId, (row['content'] ?? '').toString());
      return;
    }

    if (action == 'delete') {
      await _deleteCommentConfirm(commentId);
      return;
    }
  }

  Future<void> _editCommentDialog(String commentId, String initial) async {
    final controller = TextEditingController(text: initial);

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit comment"),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(hintText: "Update your comment..."),
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
      await supabase.rpc('edit_comment', params: {
        'comment_id_input': commentId,
        'content_input': newText,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Comment updated ✅")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Edit failed: $e")),
      );
    }
  }

  Future<void> _deleteCommentConfirm(String commentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete comment?"),
        content: const Text("This will remove the comment from view (soft delete)."),
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
      await supabase.rpc('soft_delete_comment', params: {
        'comment_id_input': commentId,
      });

      if (_replyToCommentId == commentId) _cancelInlineReply();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Comment deleted ✅")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete failed: $e")),
      );
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
            "Comment thread page (later will show post preview, filters, etc.)",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ===================== Inline reply composer =====================
  Widget _inlineReplyComposer() {
    final parentUid = _replyToUserId;
    final label = (parentUid != null && parentUid.isNotEmpty) ? _displayNameForUser(parentUid) : 'Anon';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Replying to $label', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _cancelInlineReply),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replyController,
                  decoration: const InputDecoration(
                    hintText: 'Write a reply…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _postingReply
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(icon: const Icon(Icons.send), onPressed: _postInlineReply),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viewRepliesToggle(String parentId, int count) {
    final expanded = _expandedParents.contains(parentId);
    return InkWell(
      onTap: () {
        setState(() {
          if (expanded) {
            _expandedParents.remove(parentId);
            if (_replyToCommentId == parentId) _cancelInlineReply();
          } else {
            _expandedParents.add(parentId);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 8, top: 8, bottom: 4),
        child: Row(
          children: [
            Container(width: 28, height: 1, color: const Color(0xFFDDDDDD)),
            const SizedBox(width: 8),
            Text(
              expanded ? 'Hide replies' : 'View replies ($count)',
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== Comments body =====================
  Widget _commentsBody() {
    _ensureMyAnonIdentity();

    final me = _currentUserId;

    final commentsStream = supabase.from('comments').stream(primaryKey: ['id']);
    final likesStream = supabase.from('comment_likes').stream(primaryKey: ['id']);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: likesStream,
      builder: (context, likesSnap) {
        final likes = likesSnap.data ?? [];

        final Map<String, int> likeCountByComment = {};
        final Set<String> likedByMe = {};

        for (final l in likes) {
          final cid = (l['comment_id'] ?? '').toString();
          if (cid.isEmpty) continue;

          likeCountByComment[cid] = (likeCountByComment[cid] ?? 0) + 1;

          final uid = (l['user_id'] ?? '').toString();
          if (me != null && uid.isNotEmpty && uid == me) likedByMe.add(cid);
        }

        return Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: commentsStream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Error loading comments:\n${snap.error}',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final all = (snap.data ?? [])
                      .where((c) =>
                          (c['post_id'] ?? '').toString() == widget.postId &&
                          (c['is_deleted'] == false || c['is_deleted'] == null))
                      .toList();

                  final parents = <Map<String, dynamic>>[];
                  final Map<String, List<Map<String, dynamic>>> repliesByParent = {};
                  final authorIds = <String>{};

                  for (final c in all) {
                    final uid = (c['user_id'] ?? '').toString();
                    if (uid.isNotEmpty) authorIds.add(uid);

                    final parentId = (c['parent_comment_id'] ?? '').toString();
                    if (parentId.isEmpty || parentId == 'null') {
                      parents.add(c);
                    } else {
                      repliesByParent.putIfAbsent(parentId, () => []).add(c);
                    }
                  }

                  _loadIdentitiesForUsers(authorIds);

                  parents.sort((a, b) {
                    final aT = (a['created_at'] ?? '').toString();
                    final bT = (b['created_at'] ?? '').toString();
                    return aT.compareTo(bT);
                  });

                  for (final key in repliesByParent.keys) {
                    repliesByParent[key]!.sort((a, b) {
                      final aT = (a['created_at'] ?? '').toString();
                      final bT = (b['created_at'] ?? '').toString();
                      return aT.compareTo(bT);
                    });
                  }

                  if (parents.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No comments yet')),
                      ],
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    itemCount: parents.length,
                    itemBuilder: (context, index) {
                      final p = parents[index];

                      final parentId = (p['id'] ?? '').toString();
                      final pUserId = (p['user_id'] ?? '').toString();
                      final pContent = (p['content'] ?? '').toString();
                      final pTime = _timeAgo(p['created_at']);
                      final edited = _isEdited(p);

                      final pDisplayName = pUserId.isNotEmpty ? _displayNameForUser(pUserId) : 'Anon';
                      final pAvatarColor = pUserId.isNotEmpty ? _displayColorForUser(pUserId) : Colors.grey;
                      final pInitials = _initialsFromLabel(pDisplayName);

                      final pLikeCount = likeCountByComment[parentId] ?? 0;
                      final pIsLiked = parentId.isNotEmpty && likedByMe.contains(parentId);

                      final replies = repliesByParent[parentId] ?? [];
                      final expanded = _expandedParents.contains(parentId);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: pAvatarColor,
                              child: Text(
                                pInitials,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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
                                        child: Row(
                                          children: [
                                            Text(pDisplayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                            if (edited)
                                              const Padding(
                                                padding: EdgeInsets.only(left: 6),
                                                child: Text("Edited", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (pTime.isNotEmpty)
                                        Text(pTime, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      IconButton(
                                        icon: const Icon(Icons.more_horiz, size: 18),
                                        onPressed: () => _showCommentMenu(p),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0xFFE9E9EF)),
                                    ),
                                    child: Text(pContent),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          if (parentId.isEmpty) return;
                                          _toggleLike(parentId);
                                        },
                                        child: Text(
                                          pIsLiked ? 'Unlike' : 'Like',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: pIsLiked ? Colors.blueGrey : Colors.grey,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      InkWell(
                                        onTap: () => _openInlineReply(parentId, pUserId),
                                        child: const Text('Reply',
                                            style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                                      ),
                                      const SizedBox(width: 14),
                                      if (pLikeCount > 0)
                                        Text('$pLikeCount like${pLikeCount == 1 ? '' : 's'}',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  if (_replyToCommentId == parentId) _inlineReplyComposer(),
                                  if (replies.isNotEmpty) _viewRepliesToggle(parentId, replies.length),
                                  if (replies.isNotEmpty && expanded)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        children: [
                                          for (final r in replies) _replyBubble(r, likeCountByComment, likedByMe),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                pIsLiked ? Icons.favorite : Icons.favorite_border,
                                color: pIsLiked ? Colors.redAccent : Colors.grey,
                                size: 20,
                              ),
                              onPressed: () {
                                if (parentId.isEmpty) return;
                                _toggleLike(parentId);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: const [
                  BoxShadow(blurRadius: 10, color: Color(0x11000000), offset: Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _postingComment
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(icon: const Icon(Icons.send), onPressed: _addTopLevelComment),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _replyBubble(
    Map<String, dynamic> c,
    Map<String, int> likeCountByComment,
    Set<String> likedByMe,
  ) {
    final commentId = (c['id'] ?? '').toString();
    final cUserId = (c['user_id'] ?? '').toString();
    final content = (c['content'] ?? '').toString();
    final time = _timeAgo(c['created_at']);
    final edited = _isEdited(c);

    final displayName = cUserId.isNotEmpty ? _displayNameForUser(cUserId) : 'Anon';
    final color = cUserId.isNotEmpty ? _displayColorForUser(cUserId) : Colors.grey;
    final initials = _initialsFromLabel(displayName);

    final isLiked = commentId.isNotEmpty && likedByMe.contains(commentId);
    final likeCount = likeCountByComment[commentId] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(left: 36, top: 8, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color,
            child: Text(
              initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
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
                      child: Row(
                        children: [
                          Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if (edited)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text("Edited", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ),
                        ],
                      ),
                    ),
                    if (time.isNotEmpty) Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, size: 18),
                      onPressed: () => _showCommentMenu(c),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE9E9EF)),
                  ),
                  child: Text(content),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        if (commentId.isEmpty) return;
                        _toggleLike(commentId);
                      },
                      child: Text(
                        isLiked ? 'Unlike' : 'Like',
                        style: TextStyle(
                          fontSize: 12,
                          color: isLiked ? Colors.blueGrey : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (likeCount > 0)
                      Text('$likeCount like${likeCount == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? Colors.redAccent : Colors.grey,
              size: 18,
            ),
            onPressed: () {
              if (commentId.isEmpty) return;
              _toggleLike(commentId);
            },
          ),
        ],
      ),
    );
  }

  // ===================== Build =====================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(title: const Text('Comments')),
          drawer: isWide ? null : Drawer(child: _leftSidebar(context, isWide: false)),
          body: Row(
            children: [
              if (isWide) _leftSidebar(context, isWide: true),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 900 : double.infinity),
                    child: Card(
                      elevation: 0,
                      margin: EdgeInsets.symmetric(horizontal: isWide ? 18 : 12, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: _commentsBody(),
                    ),
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

class _SideItem {
  final IconData icon;
  final String label;
  _SideItem({required this.icon, required this.label});
}
