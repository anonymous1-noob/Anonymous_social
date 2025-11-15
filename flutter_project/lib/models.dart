class Post {
  final String id;
  final String? userId;
  final String content;
  final String author;
  final int commentCount;
  final int likeCount;
  final int impressionCount;
  final bool isLiked;

  Post({
    required this.id,
    this.userId,
    required this.content,
    required this.author,
    required this.commentCount,
    required this.likeCount,
    required this.impressionCount,
    this.isLiked = false,
  });
}

class Comment {
  final String id;
  final String content;
  final String author;
  final DateTime createdAt;
  final int likeCount;
  final bool isLiked;

  Comment({
    required this.id,
    required this.content,
    required this.author,
    required this.createdAt,
    required this.likeCount,
    this.isLiked = false,
  });
}
