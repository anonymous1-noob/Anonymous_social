import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 🔥 EdgeRank function (REUSABLE)
List<Map<String, dynamic>> applyEdgeRank({
  required List<Map<String, dynamic>> posts,
  String? currentUserId,
}) {
  final now = DateTime.now();

  final scoredPosts = posts.map<Map<String, dynamic>>((post) {
    final createdAt =
        DateTime.tryParse(post['created_at'] ?? '') ?? now;

    // TIME DECAY
    final hoursSincePost = now.difference(createdAt).inHours;
    final timeDecay = 1 / (1 + (hoursSincePost / 12));

    // ENGAGEMENT
    final likeCount =
        (post['likes'] != null && post['likes'].isNotEmpty)
            ? post['likes'][0]['count'] ?? 0
            : 0;

    final commentCount =
        (post['comments'] != null && post['comments'].isNotEmpty)
            ? post['comments'][0]['count'] ?? 0
            : 0;

    final weight = (likeCount * 1.0) + (commentCount * 2.0);

    // AFFINITY
    double affinity = 1.0;

    if (currentUserId != null &&
        post['user_id'] == currentUserId) {
      affinity = 2.0;
    }

    // RANDOM BOOST (important for refresh feel)
    final randomBoost =
        (DateTime.now().millisecondsSinceEpoch % 1000) / 1000;

    final score =
        (affinity * (1 + weight) * timeDecay) + (randomBoost * 0.1);

    return {
      ...post,
      'edge_rank_score': score,
    };
  }).toList();

  scoredPosts.sort((a, b) =>
      (b['edge_rank_score'] as double)
          .compareTo(a['edge_rank_score'] as double));

  print("🔥 EdgeRank applied on ${posts.length} posts");

  return scoredPosts;
}