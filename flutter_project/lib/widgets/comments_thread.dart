import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/report_dialog.dart';

/// Instagram-like comment thread widget designed to be embedded inside a
/// DraggableScrollableSheet (bottom sheet).
///
/// - No Scaffold / AppBar inside.
/// - Uses a provided [scrollController] when used in a bottom sheet so the sheet
///   and list scroll behave correctly.
/// - Includes a sticky bottom composer for new comments.
class CommentsThread extends StatefulWidget {
  final String postId;
  final int categoryId;

  /// Pass the sheet scroll controller from DraggableScrollableSheet.
  final ScrollController? scrollController;

  /// When true, tweaks spacing to better fit bottom-sheet context.
  final bool isInBottomSheet;

  const CommentsThread({
    super.key,
    required this.postId,
    required this.categoryId,
    this.scrollController,
    this.isInBottomSheet = false,
  });

  @override
  State<CommentsThread> createState() => _CommentsThreadState();
}

class _CommentsThreadState extends State<CommentsThread> {
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

    _currentUserId = supabase.auth.currentUser?.id;

    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      setState(() {
        _currentUserId = user?.id;
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

  // -------------------- Identity --------------------

  Future<void> _ensureMyAnonIdentity() async {
    if (_ensuredMyIdentity) return;
    final me = _currentUserId;
    if (me == null) return;

    _ensuredMyIdentity = true;
    try {
      // Your DB should have this RPC from earlier iterations.
      await supabase.rpc('ensure_anon_identity', params: {'p_user_id': me});
    } catch (_) {
      // Ignore — app still works; identity falls back to defaults.
    }
  }

  Future<void> _loadIdentitiesForUsers(Set<String> userIds) async {
    if (_loadingIdentities) return;
    final missing = userIds.where((u) => !_identityByUser.containsKey(u)).toList();
    if (missing.isEmpty) return;

    _loadingIdentities = true;
    try {
      // postgrest 2.x uses `inFilter` (not `in_`).
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
      // stored as int-like string
      final parsed = int.tryParse(raw);
      if (parsed != null) return Color(parsed);
    }
    // fallback
    return const Color(0xFF94A3B8); // slate-ish
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  // -------------------- Time helpers --------------------

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

  bool _isEdited(Map<String, dynamic> c) {
    final editedAt = (c['edited_at'] ?? '').toString();
    return editedAt.isNotEmpty && editedAt != 'null';
  }

  // -------------------- Actions --------------------

  Future<void> _toggleLikeComment({
    required String commentId,
    required bool isLikedByMe,
  }) async {
    final me = _currentUserId;
    if (me == null) return;

    try {
      if (isLikedByMe) {
        await supabase
            .from('comment_likes')
            .delete()
            .match({'comment_id': commentId, 'user_id': me});
      } else {
        await supabase
            .from('comment_likes')
            .insert({'comment_id': commentId, 'user_id': me});
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _postTopLevelComment() async {
    final me = _currentUserId;
    if (me == null) return;

    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _postingComment = true);
    try {
      await _ensureMyAnonIdentity();
      await supabase.from('comments').insert({
        'post_id': widget.postId,
        'user_id': me,
        'content': text,
        'parent_comment_id': null,
        'is_deleted': false,
      });
      _commentController.clear();
      FocusScope.of(context).unfocus();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  Future<void> _postReply() async {
    final me = _currentUserId;
    if (me == null) return;

    final parentId = _replyToCommentId;
    if (parentId == null) return;

    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _postingReply = true);
    try {
      await _ensureMyAnonIdentity();
      await supabase.from('comments').insert({
        'post_id': widget.postId,
        'user_id': me,
        'content': text,
        'parent_comment_id': parentId,
        'reply_to_user_id': _replyToUserId,
        'is_deleted': false,
      });

      _replyController.clear();
      setState(() {
        _replyToCommentId = null;
        _replyToUserId = null;
      });
      FocusScope.of(context).unfocus();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _postingReply = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final me = _currentUserId;
    if (me == null) return;

    try {
      // Soft delete
      await supabase.from('comments').update({'is_deleted': true}).eq('id', commentId);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _reportComment(String commentId) async {
    final me = _currentUserId;
    if (me == null) return;

    // Use the existing report dialog helper from your project.
    await showReportDialog(
      context: context,
      targetType: 'comment',
      targetId: commentId,
    );
  }

  // -------------------- UI pieces --------------------

  Widget _avatar(String userId, {double size = 34}) {
    final name = _displayNameForUser(userId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _avatarColorForUser(userId),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }

  Widget _commentRow({
    required Map<String, dynamic> c,
    required Map<String, int> likeCountByComment,
    required Set<String> likedByMe,
    required bool isReply,
  }) {
    final id = (c['id'] ?? '').toString();
    final userId = (c['user_id'] ?? '').toString();
    final content = (c['content'] ?? '').toString();
    final time = _timeAgo(c['created_at']);
    final edited = _isEdited(c);

    final me = _currentUserId;
    final isMine = me != null && userId == me;

    final displayName = userId.isNotEmpty ? _displayNameForUser(userId) : 'Anon';
    final likes = likeCountByComment[id] ?? 0;
    final isLiked = likedByMe.contains(id);

    return Padding(
      padding: EdgeInsets.only(
        top: 10,
        bottom: 10,
        left: isReply ? 44 : 0,
        right: 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (userId.isNotEmpty) _avatar(userId, size: isReply ? 28 : 34) else const SizedBox(width: 34, height: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    if (edited)
                      const Text(
                        '• Edited',
                        style: TextStyle(color: Colors.black45, fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: const TextStyle(fontSize: 14, height: 1.25),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _toggleLikeComment(commentId: id, isLikedByMe: isLiked),
                      child: Row(
                        children: [
                          Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 18,
                            color: isLiked ? Colors.redAccent : Colors.black54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            likes.toString(),
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (!isReply)
                      InkWell(
                        onTap: () {
                          setState(() {
                            _replyToCommentId = id;
                            _replyToUserId = userId.isNotEmpty ? userId : null;
                            _expandedParents.add(id); // ensure replies visible
                          });
                          Future.delayed(const Duration(milliseconds: 10), () {
                            FocusScope.of(context).requestFocus(FocusNode());
                            // We'll focus the reply field by requesting focus in build when it appears.
                          });
                        },
                        child: const Text(
                          'Reply',
                          style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: '',
                      onSelected: (v) async {
                        if (v == 'report') {
                          await _reportComment(id);
                        } else if (v == 'delete') {
                          await _deleteComment(id);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'report', child: Text('Report')),
                        if (isMine) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.more_horiz, size: 18, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyComposer() {
    final canSend = _replyController.text.trim().isNotEmpty && !_postingReply;
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom * 0.0,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Write a reply…',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          TextButton(
            onPressed: canSend ? _postReply : null,
            child: _postingReply
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Post'),
          ),
        ],
      ),
    );
  }

  Widget _bottomComposer() {
    final canSend = _commentController.text.trim().isNotEmpty && !_postingComment;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => canSend ? _postTopLevelComment() : null,
                decoration: InputDecoration(
                  hintText: 'Add a comment…',
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            TextButton(
              onPressed: canSend ? _postTopLevelComment : null,
              child: _postingComment
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureMyAnonIdentity();

    final me = _currentUserId;

    final commentsStream = supabase.from('comments').stream(primaryKey: ['id']);
    final likesStream = supabase.from('comment_likes').stream(primaryKey: ['id']);

    final listPadding = EdgeInsets.symmetric(
      vertical: widget.isInBottomSheet ? 8 : 10,
      horizontal: 12,
    );

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
                      controller: widget.scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      children: const [
                        SizedBox(height: 64),
                        Center(child: Text('No comments yet')),
                      ],
                    );
                  }

                  return ListView.builder(
                    controller: widget.scrollController,
                    padding: listPadding,
                    itemCount: parents.length,
                    itemBuilder: (context, index) {
                      final p = parents[index];
                      final parentId = (p['id'] ?? '').toString();
                      final replies = repliesByParent[parentId] ?? [];

                      final isExpanded = _expandedParents.contains(parentId);
                      final showReplies = isExpanded ? replies : (replies.length > 2 ? replies.take(2).toList() : replies);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _commentRow(
                            c: p,
                            likeCountByComment: likeCountByComment,
                            likedByMe: likedByMe,
                            isReply: false,
                          ),

                          if (replies.isNotEmpty && !isExpanded && replies.length > 2)
                            Padding(
                              padding: const EdgeInsets.only(left: 44, bottom: 6),
                              child: InkWell(
                                onTap: () => setState(() => _expandedParents.add(parentId)),
                                child: Text(
                                  'View ${replies.length - 2} more replies',
                                  style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),

                          for (final r in showReplies)
                            _commentRow(
                              c: r,
                              likeCountByComment: likeCountByComment,
                              likedByMe: likedByMe,
                              isReply: true,
                            ),

                          if (_replyToCommentId == parentId) _replyComposer(),

                          const Divider(height: 22, color: Color(0xFFE5E7EB)),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            _bottomComposer(),
          ],
        );
      },
    );
  }
}
