import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:anonymous_social/models.dart';
import 'notifications_screen.dart';
import 'edit_post_screen.dart';
import 'package:anonymous_social/widgets/comments_sheet.dart';
import 'package:anonymous_social/widgets/report_dialog.dart';
import 'package:anonymous_social/services/block_service.dart';
import 'package:anonymous_social/services/saved_posts_service.dart';
import 'package:anonymous_social/services/poll_service.dart';
import 'package:anonymous_social/utils/hashtags.dart';
import 'tag_posts_screen.dart';
import 'profile_screen.dart';
import 'package:anonymous_social/services/edge_rank_service.dart';
import 'package:anonymous_social/services/local_prefs.dart';
import 'package:anonymous_social/models/post_model.dart';
import 'package:anonymous_social/models/user_model.dart';

enum FeedSortMode { latest, trending, edgerank }

const _ratingCoachmarkSeenKey = 'rating_slider_coachmark_seen_v1';

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
  String? _ratingUserId;
  StreamSubscription<AuthState>? _authSub;

  final Map<String, int> commentCountByPost = {};

  // Rating cache for swipe-based post scores (-5 to +5).
  final Map<String, int> _myPostRatings = {};
  final Map<String, int> _postRatingSums = {};
  final Map<String, int> _postRatingCounts = {};

  // Saved posts
  final Set<String> _savedPostIds = {};


  bool _refreshing = false;
  bool _ensuredMyIdentity = false;

  // Identity cache
  final Map<String, Map<String, dynamic>> _identityByUser = {};
  bool _loadingIdentities = false;

  // Student-safety features
  Set<String> _blockedUserIds = {};

  // UI state
  FeedSortMode _sortMode = FeedSortMode.latest;
  String _categoryName = 'All posts';

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
      setState(() {
        _currentUserId = user?.id;
        _ratingUserId = null;
      });
      _fetchInitialSaved();
      _fetchInitialRatings();
    });

    _fetchInitialSaved();
    _fetchInitialRatings();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowRatingCoachmark();
    });

    _loadBlockedUsers();
    _loadCategoryName();
  }

  @override
  void didUpdateWidget(covariant FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _loadCategoryName();
    }
  }

  Future<void> _loadBlockedUsers() async {
    final ids = await BlockService.getBlockedUserIds();
    if (!mounted) return;
    setState(() => _blockedUserIds = ids);
  }

  Future<void> _loadCategoryName() async {
    if (widget.categoryId <= 0) {
      if (!mounted) return;
      setState(() => _categoryName = 'All posts');
      return;
    }

    try {
      final row = await supabase
          .from('categories')
          .select('name')
          .eq('id', widget.categoryId)
          .maybeSingle();

      final name = (row?['name'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() => _categoryName = name.isEmpty ? 'Category' : name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _categoryName = 'Category');
    }
  }

  Future<void> _maybeShowRatingCoachmark() async {
    final prefs = await LocalPrefs.instance();
    final hasSeenCoachmark = prefs.getBool(_ratingCoachmarkSeenKey) ?? false;
    if (hasSeenCoachmark || !mounted) return;

    await prefs.setBool(_ratingCoachmarkSeenKey, true);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tip: slide 😕 left or 🔥 right to rate a post.'),
        duration: Duration(seconds: 5),
      ),
    );
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

  Future<String?> _currentPostRatingUserId() async {
    final authUser = supabase.auth.currentUser;
    final authId = authUser?.id ?? _currentUserId;
    if (authId == null) return null;
    if (_ratingUserId != null) return _ratingUserId;

    try {
      final row = await supabase
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      final publicUserId = (row?['id'] ?? '').toString();
      if (publicUserId.isNotEmpty) {
        _ratingUserId = publicUserId;
        return publicUserId;
      }
    } catch (e, st) {
      debugPrint('RATING USER LOOKUP ERROR: $e');
      debugPrint('$st');
    }

    try {
      final compactAuthId = authId.replaceAll('-', '');
      final fallbackUsername = 'user_${compactAuthId.substring(0, 12)}';
      final profile = <String, dynamic>{
        'id': authId,
        'auth_id': authId,
        'username': fallbackUsername,
      };
      final email = authUser?.email;
      if (email != null && email.trim().isNotEmpty) {
        profile['email'] = email.trim();
      }

      final inserted = await supabase
          .from('users')
          .upsert(profile, onConflict: 'auth_id')
          .select('id')
          .single();
      final publicUserId = (inserted['id'] ?? '').toString();
      if (publicUserId.isNotEmpty) {
        _ratingUserId = publicUserId;
        return publicUserId;
      }
    } catch (e, st) {
      debugPrint('RATING USER CREATE ERROR: $e');
      debugPrint('$st');
    }

    _ratingUserId = authId;
    return authId;
  }


  Future<void> _fetchInitialRatings() async {
    final me = await _currentPostRatingUserId();
    final authId = _currentUserId;
    if (me == null) return;

    try {
      final ratings = await supabase
          .from('post_ratings')
          .select('post_id, user_id, rating');

      final Map<String, int> mine = {};
      final Map<String, int> sums = {};
      final Map<String, int> counts = {};

      for (final row in ratings) {
        final pid = (row['post_id'] ?? '').toString();
        if (pid.isEmpty) continue;

        final rating = _clampRating(row['rating']);
        sums[pid] = (sums[pid] ?? 0) + rating;
        counts[pid] = (counts[pid] ?? 0) + 1;

        final uid = (row['user_id'] ?? '').toString();
        if (uid == me || uid == authId) mine[pid] = rating;
      }

      if (!mounted) return;
      setState(() {
        _myPostRatings
          ..clear()
          ..addAll(mine);
        _postRatingSums
          ..clear()
          ..addAll(sums);
        _postRatingCounts
          ..clear()
          ..addAll(counts);
      });
    } catch (e, st) {
      debugPrint('FETCH RATINGS ERROR: $e');
      debugPrint('$st');
    }
  }

  int _clampRating(dynamic value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
    return parsed.clamp(-5, 5).toInt();
  }

  String _formatSigned(num value) {
    if (value > 0) return '+$value';
    return value.toString();
  }

  double _averageRatingForPost(String postId) {
    final count = _postRatingCounts[postId] ?? 0;
    if (count == 0) return 0;
    return (_postRatingSums[postId] ?? 0) / count;
  }

  String _formatAverageRatingValue(double avg) {
    if (avg == 0) return '0.0';
    final prefix = avg > 0 ? '+' : '';
    return '$prefix${avg.toStringAsFixed(1)}';
  }

  String _formatRatingCount(int count) {
    if (count >= 1000) {
      final compact = count / 1000;
      return '${compact.toStringAsFixed(compact >= 10 ? 0 : 1)}k';
    }
    return count.toString();
  }

  Color _ratingToneColor(double avg, int count) {
    if (count == 0 || avg == 0) return const Color(0xFF64748B);
    return avg > 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C);
  }

  Color _ratingToneBackground(double avg, int count) {
    if (count == 0 || avg == 0) return const Color(0xFFF8FAFC);
    return avg > 0 ? const Color(0xFFEFFDF5) : const Color(0xFFFEF2F2);
  }

  Color _ratingToneBorder(double avg, int count) {
    if (count == 0 || avg == 0) return const Color(0xFFE2E8F0);
    return avg > 0 ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5);
  }

  IconData _ratingToneIcon(double avg, int count) {
    if (count == 0) return Icons.auto_awesome_outlined;
    if (avg > 0) return Icons.trending_up;
    if (avg < 0) return Icons.trending_down;
    return Icons.balance_outlined;
  }

  Future<void> _ratePost(String postId, int rating) async {
    final me = await _currentPostRatingUserId();
    if (me == null) return;

    final previousRating = _myPostRatings[postId] ?? 0;
    final nextRating = rating.clamp(-5, 5).toInt();
    if (nextRating == previousRating) return;

    final hadPreviousRating = _myPostRatings.containsKey(postId);
    final previousSum = _postRatingSums[postId] ?? 0;
    final previousCount = _postRatingCounts[postId] ?? 0;

    setState(() {
      _myPostRatings[postId] = nextRating;
      _postRatingSums[postId] = previousSum - previousRating + nextRating;
      _postRatingCounts[postId] = hadPreviousRating ? previousCount : previousCount + 1;
    });

    try {
      await supabase.from('post_ratings').upsert(
        {
          'post_id': postId,
          'user_id': me,
          'rating': nextRating,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'post_id,user_id',
      );
    } catch (e, st) {
      debugPrint('POST RATING ERROR: $e');
      debugPrint('$st');

      if (!mounted) return;
      setState(() {
        if (hadPreviousRating) {
          _myPostRatings[postId] = previousRating;
        } else {
          _myPostRatings.remove(postId);
        }
        _postRatingSums[postId] = previousSum;
        _postRatingCounts[postId] = previousCount;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rating failed: $e')),
      );
    }
  }

  Future<void> _fetchInitialSaved() async {
    final me = _currentUserId;
    if (me == null) return;

    final ids = await SavedPostsService.fetchSavedPostIds();
    if (!mounted) return;
    setState(() {
      _savedPostIds
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _toggleSaved(String postId) async {
    final me = _currentUserId;
    if (me == null) return;

    final wasSaved = _savedPostIds.contains(postId);
    setState(() {
      if (wasSaved) {
        _savedPostIds.remove(postId);
      } else {
        _savedPostIds.add(postId);
      }
    });

    try {
      await SavedPostsService.toggleSaved(postId: postId, shouldSave: !wasSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (wasSaved) {
          _savedPostIds.add(postId);
        } else {
          _savedPostIds.remove(postId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  Widget _pollSection({required String postId}) {
    return FutureBuilder<PollBundle?>(
      future: PollService.getPollForPost(postId: postId),
      builder: (context, snap) {
        final poll = snap.data;
        if (poll == null) return const SizedBox.shrink();

        final totalVotes = poll.options.fold<int>(0, (a, b) => a + b.votes);
        final my = poll.myOptionId;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.poll_outlined, size: 18),
                    const SizedBox(width: 6),
                    const Text('Poll', style: TextStyle(fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Text('$totalVotes votes', style: const TextStyle(color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 10),
                ...poll.options.map((o) {
                  final isMine = my != null && my == o.id;
                  final pct = totalVotes == 0 ? 0.0 : (o.votes / totalVotes);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: (_currentUserId == null)
                          ? null
                          : () async {
                              try {
                                await PollService.vote(pollId: poll.pollId, optionId: o.id);
                                if (!mounted) return;
                                setState(() {});
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Vote failed: $e')),
                                );
                              }
                            },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isMine ? Colors.black87 : const Color(0xFFE5E7EB),
                            width: isMine ? 1.2 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.text, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 8,
                                      backgroundColor: const Color(0xFFF3F4F6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('${o.votes}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
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

                if (!isMine && postUserId.isNotEmpty) ...[
                  ListTile(
                    leading: const Icon(Icons.block_outlined),
                    title: const Text('Block user'),
                    subtitle: const Text('Hide their posts & comments on this device'),
                    onTap: () => Navigator.pop(ctx, 'block'),
                  ),
                ],
                if (isMine) ...[
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () => Navigator.pop(ctx, 'edit'),
                  ),
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

    if (action == 'block') {
      if (postUserId.isNotEmpty) {
        await BlockService.blockUser(postUserId);
        await _loadBlockedUsers();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked. You won\'t see their posts/comments.')),
        );
      }
      return;
    }

    if (action == 'edit') {
      final content = (post['content'] ?? '').toString();
      final createdAtRaw = post['created_at'];
      final createdAt = DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now();
      final mediaUrl = (post['media_url'] ?? '').toString().trim();
      final postObj = Post(
        id: postId,
        content: content,
        anonymousName: 'Anonymous',
        impressions: 0,
        likes: 0,
        createdAt: createdAt,
        mediaUrl: mediaUrl.isEmpty ? null : mediaUrl,
      );

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditPostScreen(post: postObj)),
      );
      return;
    }

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
          const Text("Tip: Slide 😕 or 🔥 to rate, 💬 to comment.",
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
            ..._buildHashtagSpans(' $caption'),
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
                ..._buildHashtagSpans(' $caption'),
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
              ..._buildHashtagSpans(' $shortCaption '),
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



  List<InlineSpan> _buildHashtagSpans(String text) {
    final tokens = tokenizeHashtags(text);
    return tokens.map((t) {
      if (!t.isTag) return TextSpan(text: t.text);
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TagPostsScreen(tag: t.text)),
          ),
          child: Text(
            t.text,
            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }).toList();
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

    final isSaved = _savedPostIds.contains(postId);

    final commentCount = commentCountByPost[postId] ?? 0;

    bool expanded = false;

    final time = _timeAgo(createdAt);

    var draftRating = (_myPostRatings[postId] ?? 0).toDouble();
    var isRatingSliderActive = false;
    var lastHapticRating = draftRating.round();

    return StatefulBuilder(
      builder: (context, setLocal) {
        final myRating = draftRating.round();
        final ratingColor = myRating > 0
            ? const Color(0xFF16A34A)
            : (myRating < 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B));
        final ratingEmoji = myRating > 0 ? '🔥' : (myRating < 0 ? '😕' : '😐');
        final ratingCount = _postRatingCounts[postId] ?? 0;
        final avgRating = _averageRatingForPost(postId);
        final avgToneColor = _ratingToneColor(avgRating, ratingCount);
        final avgToneBackground = _ratingToneBackground(avgRating, ratingCount);
        final avgToneBorder = _ratingToneBorder(avgRating, ratingCount);

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
                    InkWell(
                      onTap: authorId.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PublicProfileScreen(userId: authorId),
                                ),
                              );
                            },
                      customBorder: const CircleBorder(),
                      child: Container(
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
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                              ),
                              if (editedAt != null)
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Text(
                                    "• Edited",
                                    style: TextStyle(fontSize: 12, color: Colors.black45),
                                  ),
                                ),
                            ],
                          ),
                          if (time.isNotEmpty)
                            Text(
                              time,
                              style: const TextStyle(fontSize: 12, color: Colors.black45),
                            ),
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

              // Poll (if this post has one)
              _pollSection(postId: postId),

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

              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 6, 0),
                child: Row(
                  children: [
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
                      onPressed: () => _sharePost(postId: postId),
                      icon: const Icon(Icons.send_outlined),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: avgToneBackground,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: avgToneBorder),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0D000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _ratingToneIcon(avgRating, ratingCount),
                                    size: 16,
                                    color: avgToneColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    ratingCount == 0
                                        ? 'New rating'
                                        : '${_formatAverageRatingValue(avgRating)} avg',
                                    style: TextStyle(
                                      color: avgToneColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.groups_2_outlined,
                                    size: 15,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    ratingCount == 0
                                        ? 'Be first'
                                        : '${_formatRatingCount(ratingCount)} ${ratingCount == 1 ? 'rating' : 'ratings'}',
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      splashRadius: 20,
                      onPressed: () => _toggleSaved(postId),
                      icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    const Text(
                      'Rate this post',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$ratingEmoji ${_formatSigned(myRating)}',
                      style: TextStyle(
                        color: ratingColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Text('😕', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: ratingColor,
                            inactiveTrackColor: const Color(0xFFE2E8F0),
                            overlayColor: ratingColor.withOpacity(0.14),
                            thumbColor: ratingColor,
                            trackHeight: isRatingSliderActive ? 8 : 6,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius:
                                  isRatingSliderActive ? 12 : 10,
                            ),
                            valueIndicatorColor: ratingColor,
                            valueIndicatorTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          child: Slider(
                            min: -5,
                            max: 5,
                            divisions: 10,
                            value: draftRating,
                            label: '$ratingEmoji ${_formatSigned(myRating)}',
                            onChangeStart: (_) {
                              HapticFeedback.lightImpact();
                              setLocal(() => isRatingSliderActive = true);
                            },
                            onChanged: (value) {
                              final nextRating = value.round();
                              if (nextRating != lastHapticRating) {
                                HapticFeedback.selectionClick();
                                lastHapticRating = nextRating;
                              }
                              setLocal(() => draftRating = nextRating.toDouble());
                            },
                            onChangeEnd: (value) {
                              final nextRating = value.round();
                              setLocal(() {
                                draftRating = nextRating.toDouble();
                                isRatingSliderActive = false;
                              });
                              _ratePost(postId, nextRating);
                            },
                          ),
                        ),
                      ),
                    ),
                    const Text('🔥', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Future<void> _sharePost({required String postId}) async {
    final link = 'https://anonymous-social.app/post/$postId';
    await Share.share(link);
  }

  @override
  Widget build(BuildContext context) {
    _ensureMyAnonIdentity();

    final postsStream = supabase.from('posts').stream(primaryKey: ['id']);
    final postCategoriesStream = (widget.categoryId <= 0)
        ? null
        : supabase
            .from('post_categories')
            .stream(primaryKey: ['post_id', 'category_id'])
            .eq('category_id', widget.categoryId);
    final commentsStream = supabase.from('comments').stream(primaryKey: ['id']);

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
                    await _fetchInitialRatings();
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

                      final catStream = (widget.categoryId <= 0)
                          ? Stream.value(<Map<String, dynamic>>[])
                          : (postCategoriesStream ?? Stream.value(<Map<String, dynamic>>[]));

                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: catStream,
                        builder: (context, catSnap) {
                          final postIds = <String>{};
                          if (widget.categoryId > 0) {
                            for (final row in (catSnap.data ?? const [])) {
                              final pid = (row['post_id'] ?? '').toString();
                              if (pid.isNotEmpty) postIds.add(pid);
                            }
                          }

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
                                    final uid = (p['user_id'] ?? '').toString();
                                    if (uid.isEmpty) return true;
                                    return !_blockedUserIds.contains(uid);
                                  })
                                  .where((p) => p['is_public'] == true)
                                  .where((p) {
                                    if (widget.categoryId <= 0) return true;
                                    final id = (p['id'] ?? '').toString();
                                    return id.isNotEmpty && postIds.contains(id);
                                  })
                                  .toList();

                          // =====================================================
                          // INJECT RATING + ENGAGEMENT DATA
                          // =====================================================

                          for (final p in posts) {
                            final pid = (p['id'] ?? '').toString();

                            final ratingCount = _postRatingCounts[pid] ?? 0;

                            final avgRating = ratingCount == 0
                                ? 0.0
                                : (_postRatingSums[pid]! / ratingCount);

                            p['avg_rating'] = avgRating;

                            p['rating_count'] = ratingCount;

                            p['likes_count'] = 0;

                            p['comments_count'] =
                                commentCountByPost[pid] ?? 0;

                            // Optional defaults
                            p['shares_count'] ??= 0;
                            p['bookmarks_count'] ??= 0;
                            p['dwell_time'] ??= 0.0;
                            p['report_count'] ??= 0;
                          }

                          // Sorting: Latest vs Trending
                          posts.sort((a, b) {
                            if (_sortMode == FeedSortMode.latest) {
                              final aT = (a['created_at'] ?? '').toString();
                              final bT = (b['created_at'] ?? '').toString();
                              return bT.compareTo(aT);
                            }
                            if (_sortMode == FeedSortMode.edgerank) {
                              final postA = PostModel.fromMap(a);
                              final postB = PostModel.fromMap(b);

                              // TEMP anonymous users
                              // Later you can load real profiles
                              final currentUser = UserModel.anonymous();

                              final authorA = UserModel.anonymous();

                              final authorB = UserModel.anonymous();

                              final sB = EdgeRankService.calculatePostScore(
                                post: postB,
                                currentUser: currentUser,
                                author: authorB,
                              );

                              final sA = EdgeRankService.calculatePostScore(
                                post: postA,
                                currentUser: currentUser,
                                author: authorA,
                              );

                              return sB.compareTo(sA);
                            }

                            double score(Map<String, dynamic> p) {
                              final pid = (p['id'] ?? '').toString();
                              final ratingCount = _postRatingCounts[pid] ?? 0;
                              final ratingSum = _postRatingSums[pid] ?? 0;
                              final avgRating = ratingCount == 0 ? 0.0 : ratingSum / ratingCount;
                              final comments = commentCountByPost[pid] ?? 0;

                              final createdAt = DateTime.tryParse((p['created_at'] ?? '').toString()) ?? DateTime.now();
                              final ageHrs = DateTime.now().difference(createdAt.toLocal()).inMinutes / 60.0;

                              // Trending now uses post ratings instead of post likes.
                              final engagement = (avgRating * ratingCount) + (comments * 3);
                              final denom = (ageHrs + 2.0);
                              return engagement / denom;
                            }

                            final sB = score(b);
                            final sA = score(a);
                            final cmp = sB.compareTo(sA);
                            if (cmp != 0) return cmp;
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

                              return Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 720),
                                  child: Column(
                                    children: [
                                      // --- Student-friendly header ---
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
                                        child: Row(
                                          children: [
                                            const SizedBox(width: 8),
                                            const Spacer(),
                                            SegmentedButton<FeedSortMode>(
                                              segments: const <ButtonSegment<FeedSortMode>>[
                                                ButtonSegment(value: FeedSortMode.latest, label: Text('Latest')),
                                                ButtonSegment(value: FeedSortMode.trending, label: Text('Trending')),
                                                ButtonSegment(value: FeedSortMode.edgerank, label: Text('For You')), // 🔥 ADD THIS
                                              ],
                                              selected: <FeedSortMode>{_sortMode},
                                              onSelectionChanged: (v) {
                                                if (v.isEmpty) return;
                                                setState(() => _sortMode = v.first);
                                              },
                                              style: const ButtonStyle(
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: ListView.builder(
                                          physics: const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.only(bottom: 18),
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
                                    ],
                                  ),
                                ),
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
}
