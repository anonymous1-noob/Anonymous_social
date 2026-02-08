class Post {
  // Bug #1 Fix: The ID is a String (UUID).
  final String id;
  final String content;
  final String anonymousName;
  final int impressions;
  final int likes;
  final DateTime createdAt;
  final String? mediaUrl;

  Post({
    required this.id,
    required this.content,
    required this.anonymousName,
    required this.impressions,
    required this.likes,
    required this.createdAt,
    this.mediaUrl,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    int _parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    // Bug #3 Fix: Correctly handle the anonymous flag.
    // If the post is anonymous, use 'Anonymous'. Otherwise, try to get the user's display name.
    final isAnonymous = json['anonymous'] as bool? ?? true;
    final author = json['users'];
    final authorName = (author is Map) ? author['display_name'] as String? : null;

    return Post(
      id: json['id'] as String,
      content: json['content'] ?? '',
      anonymousName: isAnonymous ? 'Anonymous' : (authorName ?? 'User'),
      impressions: _parseInt(json['impression_count']),
      likes: _parseInt(json['like_count']),
      createdAt: DateTime.parse(json['created_at']),
      mediaUrl: json['media_url'],
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
      mediaUrl: mediaUrl,
    );
  }
}

/// ----------------------------
/// COMMENT MODEL
/// ----------------------------
class Comment {
  final String id;
  final String postId;
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
      id: json['id'] as String,
      postId: json['post_id'] as String,
      text: json['text'] ?? '',
      anonymousName: json['anonymous_name'] ?? 'Anonymous',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
