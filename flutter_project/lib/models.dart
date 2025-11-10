class Post {
  final String id;
  final String content;
  final String author;
  final int commentCount;
  int likeCount;
  bool isLiked;

  Post({
    required this.id,
    required this.content,
    required this.author,
    required this.commentCount,
    required this.likeCount,
    this.isLiked = false,
  });
}

class Comment {
  final String id;
  final String content;
  final String author;
  final DateTime createdAt;
  int likeCount;
  bool isLiked;

  Comment({
    required this.id,
    required this.content,
    required this.author,
    required this.createdAt,
    required this.likeCount,
    this.isLiked = false,
  });
}
