import 'dart:math';

import 'package:flutter/material.dart';

import 'package:anonymous_social/models/post_model.dart';
import 'package:anonymous_social/models/user_model.dart';
import 'package:anonymous_social/services/edge_rank_service.dart';

class FeedProvider extends ChangeNotifier {
  // =========================================================
  // FEED STATE
  // =========================================================

  List<Map<String, dynamic>> _posts = [];

  List<Map<String, dynamic>> get posts => _posts;

  bool _isLoading = false;

  bool get isLoading => _isLoading;

  bool _hasMore = true;

  bool get hasMore => _hasMore;

  String? _error;

  String? get error => _error;

  // =========================================================
  // PAGINATION
  // =========================================================

  int _page = 1;

  final int _limit = 20;

  // =========================================================
  // MAIN FEED LOADER
  // =========================================================

  Future<void> loadFeed({
    required UserModel currentUser,
    required Future<List<Map<String, dynamic>>> Function(
      int page,
      int limit,
    ) fetchPosts,
  }) async {
    try {
      _isLoading = true;
      _error = null;

      notifyListeners();

      final rawPosts = await fetchPosts(_page, _limit);

      if (rawPosts.isEmpty) {
        _hasMore = false;

        _isLoading = false;

        notifyListeners();

        return;
      }

      final rankedPosts = await _rankPosts(
        rawPosts: rawPosts,
        currentUser: currentUser,
      );

      if (_page == 1) {
        _posts = rankedPosts;
      } else {
        _posts.addAll(rankedPosts);
      }

      _injectDiscoveryPosts();

      _page++;

      _isLoading = false;

      notifyListeners();
    } catch (e) {
      _error = e.toString();

      _isLoading = false;

      notifyListeners();
    }
  }

  // =========================================================
  // REFRESH FEED
  // =========================================================

  Future<void> refreshFeed({
    required UserModel currentUser,
    required Future<List<Map<String, dynamic>>> Function(
      int page,
      int limit,
    ) fetchPosts,
  }) async {
    _page = 1;

    _posts.clear();

    _hasMore = true;

    await loadFeed(
      currentUser: currentUser,
      fetchPosts: fetchPosts,
    );
  }

  // =========================================================
  // EDGE RANK SORTING
  // =========================================================

  Future<List<Map<String, dynamic>>> _rankPosts({
    required List<Map<String, dynamic>> rawPosts,
    required UserModel currentUser,
  }) async {
    final List<Map<String, dynamic>> rankedPosts = [];

    for (final data in rawPosts) {
      try {
        final post = PostModel(
          id: data['id'] ?? '',
          userId: data['user_id'] ?? '',
          content: data['content'] ?? '',
          likesCount: data['likes_count'] ?? 0,
          commentsCount: data['comments_count'] ?? 0,
          sharesCount: data['shares_count'] ?? 0,
          bookmarksCount: data['bookmarks_count'] ?? 0,
          reportCount: data['report_count'] ?? 0,
          avgRating: (data['avg_rating'] ?? 0).toDouble(),
          ratingCount: data['rating_count'] ?? 0,
          createdAt: DateTime.tryParse(
                data['created_at'] ?? '',
              ) ??
              DateTime.now(),
          dwellTime: (data['dwell_time'] ?? 0).toDouble(),
          tags: List<String>.from(data['tags'] ?? []),
          isDeleted: data['is_deleted'] ?? false,
        );

        final authorData =
            Map<String, dynamic>.from(data['author'] ?? {});

        final author = UserModel(
          id: authorData['id'] ?? '',
          reputationScore:
              (authorData['reputation_score'] ?? 0.5)
                  .toDouble(),
          interestedTags: [],
          totalPosts: authorData['total_posts'] ?? 0,
          historicalAvgRating:
              (authorData['historical_avg_rating'] ?? 0)
                  .toDouble(),
          reportsReceived:
              authorData['reports_received'] ?? 0,
          accountCreatedAt: DateTime.tryParse(
                authorData['created_at'] ?? '',
              ) ??
              DateTime.now(),
        );

        final score = EdgeRankService.calculatePostScore(
          post: post,
          currentUser: currentUser,
          author: author,
        );

        rankedPosts.add({
          'post': data,
          'score': score,
        });
      } catch (e) {
        debugPrint('Ranking Error: $e');
      }
    }

    // =====================================================
    // SORT POSTS BY SCORE
    // =====================================================

    rankedPosts.sort(
      (a, b) =>
          (b['score'] as double).compareTo(a['score'] as double),
    );
    print('================ RANKED POSTS ================');

    for (final item in rankedPosts) {
      print(
        'Rating: ${item['post']['avg_rating']} | '
        'Score: ${item['score']} | '
        'Post: ${item['post']['content']}',
      );
    }
    print('==============================================');

    return rankedPosts
        .map((e) => e['post'] as Map<String, dynamic>)
        .toList();
  }

  // =========================================================
  // RANDOM DISCOVERY POSTS
  // =========================================================

  void _injectDiscoveryPosts() {
    if (_posts.length < 10) {
      return;
    }

    final random = Random();

    final shuffled = List<Map<String, dynamic>>.from(_posts);

    shuffled.shuffle();

    final discoveryCount = (_posts.length * 0.05).ceil();

    final discoveryPosts = shuffled.take(discoveryCount).toList();

    for (final discoveryPost in discoveryPosts) {
      final randomIndex = random.nextInt(_posts.length);

      _posts.insert(randomIndex, discoveryPost);
    }
  }

  // =========================================================
  // LIKE UPDATE
  // =========================================================

  void updateLike({
    required String postId,
    required bool isLiked,
  }) {
    final index = _posts.indexWhere(
      (post) => post['id'] == postId,
    );

    if (index == -1) {
      return;
    }

    final currentLikes = _posts[index]['likes_count'] ?? 0;

    _posts[index]['likes_count'] =
        isLiked ? currentLikes + 1 : max<int>(0, currentLikes - 1);

    notifyListeners();
  }

  // =========================================================
  // COMMENT UPDATE
  // =========================================================

  void updateCommentCount({
    required String postId,
  }) {
    final index = _posts.indexWhere(
      (post) => post['id'] == postId,
    );

    if (index == -1) {
      return;
    }

    _posts[index]['comments_count'] =
        (_posts[index]['comments_count'] ?? 0) + 1;

    notifyListeners();
  }

  // =========================================================
  // SHARE UPDATE
  // =========================================================

  void updateShareCount({
    required String postId,
  }) {
    final index = _posts.indexWhere(
      (post) => post['id'] == postId,
    );

    if (index == -1) {
      return;
    }

    _posts[index]['shares_count'] =
        (_posts[index]['shares_count'] ?? 0) + 1;

    notifyListeners();
  }

  // =========================================================
  // BOOKMARK UPDATE
  // =========================================================

  void updateBookmarkCount({
    required String postId,
    required bool bookmarked,
  }) {
    final index = _posts.indexWhere(
      (post) => post['id'] == postId,
    );

    if (index == -1) {
      return;
    }

    final current = _posts[index]['bookmarks_count'] ?? 0;

    _posts[index]['bookmarks_count'] = bookmarked
                                ? current + 1
                                : max<int>(0, current - 1);

    notifyListeners();
  }

  // =========================================================
  // RATING UPDATE
  // =========================================================

  void updateRating({
    required String postId,
    required double newRating,
  }) {
    final index = _posts.indexWhere(
      (post) => post['id'] == postId,
    );

    if (index == -1) {
      return;
    }

    final oldAvg =
        (_posts[index]['avg_rating'] ?? 0).toDouble();

    final oldCount = _posts[index]['rating_count'] ?? 0;

    final totalScore = (oldAvg * oldCount) + newRating;

    final newCount = oldCount + 1;

    final updatedAvg = totalScore / newCount;

    _posts[index]['avg_rating'] = updatedAvg;

    _posts[index]['rating_count'] = newCount;

    notifyListeners();
  }

  // =========================================================
  // REMOVE POST
  // =========================================================

  void removePost(String postId) {
    _posts.removeWhere((post) => post['id'] == postId);

    notifyListeners();
  }

  // =========================================================
  // INSERT NEW POST
  // =========================================================

  void insertNewPost(Map<String, dynamic> post) {
    _posts.insert(0, post);

    notifyListeners();
  }

  // =========================================================
  // REPORT POST
  // =========================================================

  void reportPost(String postId) {
    final index = _posts.indexWhere(
      (post) => post['id'] == postId,
    );

    if (index == -1) {
      return;
    }

    _posts[index]['report_count'] =
        (_posts[index]['report_count'] ?? 0) + 1;

    notifyListeners();
  }

  // =========================================================
  // CLEAR PROVIDER
  // =========================================================

  void clearFeed() {
    _posts.clear();

    _page = 1;

    _hasMore = true;

    _error = null;

    notifyListeners();
  }
}