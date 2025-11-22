import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

class PostPopup extends StatefulWidget {
  final Post post;
  final Function refreshParent;

  const PostPopup({
    Key? key,
    required this.post,
    required this.refreshParent,
  }) : super(key: key);

  @override
  _PostPopupState createState() => _PostPopupState();
}

class _PostPopupState extends State<PostPopup> {
  final client = Supabase.instance.client;
  List<Map<String, dynamic>> comments = [];
  bool loading = true;
  bool sending = false;
  final TextEditingController commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadComments();
  }

  Future<void> loadComments() async {
    final res = await client
        .from("comments")
        .select('id, content, users(display_name)')
        .eq("post_id", widget.post.id)
        .order("created_at", ascending: true);

    setState(() {
      comments = res;
      loading = false;
    });
  }

  Future<void> sendComment() async {
    if (commentCtrl.text.trim().isEmpty) return;

    setState(() => sending = true);

    await client.rpc("add_post_comment", params: {
      "post_id_input": widget.post.id,
      "content_input": commentCtrl.text.trim(),
    });

    commentCtrl.clear();
    sending = false;

    await loadComments();
    widget.refreshParent();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      width: 700,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // HEADER —
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.post.author,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),

          const SizedBox(height: 8),

          // POST CONTENT
          Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.post.content, style: const TextStyle(fontSize: 16)),
          ),

          const SizedBox(height: 20),

          // COMMENTS SECTION
          Align(
            alignment: Alignment.centerLeft,
            child: const Text(
              "Comments",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),

          loading
              ? const CircularProgressIndicator()
              : comments.isEmpty
                  ? const Text("No comments yet.")
                  : Container(
                      height: 250,
                      child: ListView.builder(
                        itemCount: comments.length,
                        itemBuilder: (context, i) {
                          final c = comments[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const CircleAvatar(radius: 16),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c['users']?['display_name'] ?? "User",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(c['content']),
                                      const SizedBox(height: 6),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ),

          const SizedBox(height: 10),

          // COMMENT INPUT
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: commentCtrl,
                  decoration: InputDecoration(
                    hintText: "Write a comment...",
                    filled: true,
                    fillColor: Colors.grey.shade200,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              sending
                  ? const CircularProgressIndicator()
                  : IconButton(
                      icon: const Icon(Icons.send, color: Colors.blue),
                      onPressed: sendComment,
                    )
            ],
          ),
        ],
      ),
    );
  }
}
