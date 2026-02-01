import 'package:flutter/material.dart';

import '../widgets/comments_thread.dart';

/// Optional full-screen comments page (kept for deep-links / desktop).
/// In the Instagram-like flow (Option A), comments open as a bottom sheet.
/// This screen is still useful if you want a dedicated route later.
class CommentsScreen extends StatelessWidget {
  final String postId;
  final int categoryId;

  const CommentsScreen({
    super.key,
    required this.postId,
    required this.categoryId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: const Text('Comments')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            elevation: 0,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: CommentsThread(
              postId: postId,
              categoryId: categoryId,
            ),
          ),
        ),
      ),
    );
  }
}
