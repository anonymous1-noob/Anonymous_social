/// Defines the data models used throughout the application.

/// Represents a single post in the feed.
class Post {
  /// The unique identifier for the post (UUID).
  final String id;

  /// The ID of the user who created the post. This can be null if the post is anonymous.
  final String? userId;

  /// The main text content of the post.
  final String content;

  /// The display name of the author. This will be "Anonymous" for anonymous posts.
  final String author;

  /// The total number of comments on the post.
  final int commentCount;

  /// The total number of likes on the post.
  final int likeCount;

  /// The total number of times the post has been viewed (impressions).
  final int impressionCount;

  /// Whether the currently logged-in user has liked this post.
  /// This is managed locally in the UI for instant feedback.
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

/// Represents a single comment on a post.
class Comment {
  /// The unique identifier for the comment (UUID).
  final String id;

  /// The text content of the comment.
  final String content;

  /// The display name of the author.
  final String author;

  /// The timestamp when the comment was created.
  final DateTime createdAt;

  /// The total number of likes on the comment.
  final int likeCount;

  /// Whether the currently logged-in user has liked this comment.
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
