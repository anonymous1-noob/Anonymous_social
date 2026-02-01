class Post {
  final int id;
  final String content;
  final String anonymousName;
  final int impressions;
  final int likes;
  final DateTime createdAt;

  Post({
    required this.id,
    required this.content,
    required this.anonymousName,
    required this.impressions,
    required this.likes,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      content: json['content'],
      anonymousName: json['anonymous_name'] ?? 'Anonymous',
      impressions: json['impressions'] ?? 0,
      likes: json['likes'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Post copyWith({
    int? impressions,
    int? likes,
  }) {
    return Post(
      id: id,
      content: content,
      anonymousName: anonymousName,
      impressions: impressions ?? this.impressions,
      likes: likes ?? this.likes,
      createdAt: createdAt,
    );
  }
}

/// ----------------------------
/// COMMENT MODEL
/// ----------------------------
class Comment {
  final int id;
  final int postId;
  final String text;
  final String anonymousName;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.postId,
    required this.text,
    required this.anonymousName,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      postId: json['post_id'],
      text: json['text'],
      anonymousName: json['anonymous_name'] ?? 'Anonymous',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
