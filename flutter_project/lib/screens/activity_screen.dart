import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Activity screen for students.
///
/// This shows **your own activity** (what *you* did):
/// - You posted
/// - You liked
/// - You commented
///
/// "On you" notifications are already covered by the Notifications page, so
/// this screen intentionally does not duplicate that.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _client = Supabase.instance.client;

  bool _loading = false;
  String? _error;

  List<_ActivityItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _loadYourActivity(me);

      if (!mounted) return;
      setState(() => _items = items);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load activity.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_ActivityItem>> _loadYourActivity(String me) async {
    final items = <_ActivityItem>[];

    // 1) Your posts
    final myPosts = await _client
        .from('posts')
        .select('id, content, created_at')
        .eq('user_id', me)
        .eq('is_deleted', false)
        .order('created_at', ascending: false)
        .limit(60);

    final postPreviewById = <String, String>{};

    for (final p in (myPosts as List)) {
      final m = p as Map;
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final content = (m['content'] ?? '').toString().trim();
      final preview = content.length > 80 ? '${content.substring(0, 80)}…' : content;
      postPreviewById[id] = preview;

      final when = DateTime.tryParse((m['created_at'] ?? '').toString()) ?? DateTime.now();
      items.add(_ActivityItem(
        type: _ActivityType.post,
        postId: id,
        postPreview: preview,
        when: when,
        extraText: null,
      ));
    }

    // 2) Your likes
    List<Map<String, dynamic>> likeRows = [];
    try {
      final likes = await _client
          .from('post_likes')
          .select('post_id, created_at')
          .eq('user_id', me)
          .order('created_at', ascending: false)
          .limit(80);
      likeRows = (likes as List).cast<Map<String, dynamic>>();
    } catch (_) {
      likeRows = [];
    }

    final likedPostIds = likeRows
        .map((r) => (r['post_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (likedPostIds.isNotEmpty) {
      final likedPosts = await _client
          .from('posts')
          .select('id, content')
          .inFilter('id', likedPostIds)
          .limit(200);

      for (final p in (likedPosts as List)) {
        final m = p as Map;
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final content = (m['content'] ?? '').toString().trim();
        postPreviewById[id] = content.length > 80 ? '${content.substring(0, 80)}…' : content;
      }
    }

    for (final r in likeRows) {
      final pid = (r['post_id'] ?? '').toString();
      if (pid.isEmpty) continue;
      final when = DateTime.tryParse((r['created_at'] ?? '').toString()) ?? DateTime.now();
      items.add(_ActivityItem(
        type: _ActivityType.like,
        postId: pid,
        postPreview: postPreviewById[pid] ?? '',
        when: when,
        extraText: null,
      ));
    }

    // 3) Your comments
    List<Map<String, dynamic>> commentRows = [];
    try {
      final comments = await _client
          .from('comments')
          .select('id, post_id, text, created_at')
          .eq('user_id', me)
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(80);
      commentRows = (comments as List).cast<Map<String, dynamic>>();
    } catch (_) {
      commentRows = [];
    }

    final commentedPostIds = commentRows
        .map((r) => (r['post_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (commentedPostIds.isNotEmpty) {
      final commentPosts = await _client
          .from('posts')
          .select('id, content')
          .inFilter('id', commentedPostIds)
          .limit(200);
      for (final p in (commentPosts as List)) {
        final m = p as Map;
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final content = (m['content'] ?? '').toString().trim();
        postPreviewById[id] = content.length > 80 ? '${content.substring(0, 80)}…' : content;
      }
    }

    for (final r in commentRows) {
      final pid = (r['post_id'] ?? '').toString();
      if (pid.isEmpty) continue;
      final when = DateTime.tryParse((r['created_at'] ?? '').toString()) ?? DateTime.now();
      final text = (r['text'] ?? '').toString().trim();
      final preview = text.length > 90 ? '${text.substring(0, 90)}…' : text;

      items.add(_ActivityItem(
        type: _ActivityType.comment,
        postId: pid,
        postPreview: postPreviewById[pid] ?? '',
        when: when,
        extraText: preview,
      ));
    }

    items.sort((a, b) => b.when.compareTo(a.when));
    return items.take(120).toList();
  }

  String _timeAgo(DateTime dt) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (!_loading && _items.isEmpty && _error == null) ...[
              const SizedBox(height: 60),
              const Icon(Icons.history, size: 44, color: Colors.black38),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'No activity yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Like, comment, or post to see your activity here.',
                  style: TextStyle(color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            for (final item in _items) ...[
              _ActivityTile(
                item: item,
                timeAgo: _timeAgo(item.when),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

enum _ActivityType {
  post,
  like,
  comment,
}

class _ActivityItem {
  final _ActivityType type;
  final String postId;
  final String postPreview;
  final DateTime when;
  final String? extraText;

  _ActivityItem({
    required this.type,
    required this.postId,
    required this.postPreview,
    required this.when,
    required this.extraText,
  });
}

class _ActivityTile extends StatelessWidget {
  final _ActivityItem item;
  final String timeAgo;

  const _ActivityTile({required this.item, required this.timeAgo});

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String title;
    late final Color iconColor;

    switch (item.type) {
      case _ActivityType.post:
        icon = Icons.edit_note;
        title = 'You posted';
        iconColor = Colors.black87;
        break;
      case _ActivityType.like:
        icon = Icons.favorite;
        title = 'You liked a post';
        iconColor = Colors.redAccent;
        break;
      case _ActivityType.comment:
        icon = Icons.chat_bubble_outline;
        title = 'You commented';
        iconColor = Colors.black87;
        break;
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Future enhancement: open the post and scroll.
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          timeAgo,
                          style: const TextStyle(color: Colors.black45, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (item.postPreview.isNotEmpty)
                      Text(
                        item.postPreview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87, height: 1.2),
                      ),
                    if (item.extraText != null && item.extraText!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.extraText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
