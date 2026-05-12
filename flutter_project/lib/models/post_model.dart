class PostModel {
  final String id;

  final String userId;

  final String content;

  final int likesCount;

  final int commentsCount;

  final int sharesCount;

  final int bookmarksCount;

  final int reportCount;

  final double avgRating;

  final int ratingCount;

  final DateTime createdAt;

  final double dwellTime;

  final List<String> tags;

  final bool isDeleted;

  PostModel({
    required this.id,
    required this.userId,
    required this.content,
    required this.likesCount,
    required this.commentsCount,
    required this.sharesCount,
    required this.bookmarksCount,
    required this.reportCount,
    required this.avgRating,
    required this.ratingCount,
    required this.createdAt,
    required this.dwellTime,
    required this.tags,
    required this.isDeleted,
  });

  factory PostModel.fromMap(Map<String, dynamic> map) {
    return PostModel(
      id: (map['id'] ?? '').toString(),

      userId: (map['user_id'] ?? '').toString(),

      content: (map['content'] ?? '').toString(),

      likesCount: map['likes_count'] ?? 0,

      commentsCount: map['comments_count'] ?? 0,

      sharesCount: map['shares_count'] ?? 0,

      bookmarksCount: map['bookmarks_count'] ?? 0,

      reportCount: map['report_count'] ?? 0,

      avgRating:
          (map['avg_rating'] ?? 0).toDouble(),

      ratingCount:
          map['rating_count'] ?? 0,

      createdAt:
          DateTime.tryParse(
            (map['created_at'] ?? '')
                .toString(),
          ) ??
          DateTime.now(),

      dwellTime:
          (map['dwell_time'] ?? 0)
              .toDouble(),

      tags:
          map['tags'] != null
              ? List<String>.from(
                  map['tags'],
                )
              : [],

      isDeleted:
          map['is_deleted'] ?? false,
    );
  }
}