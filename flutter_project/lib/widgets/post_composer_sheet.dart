import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/category_provider.dart';
import '../services/rate_limit_service.dart';

enum ComposerPostType { text, poll }

Future<void> showPostComposerSheet({
  required BuildContext context,
  required int categoryId, // kept for backward-compat default
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => PostComposerSheet(defaultCategoryId: categoryId),
  );
}

class PostComposerSheet extends ConsumerStatefulWidget {
  const PostComposerSheet({super.key, this.defaultCategoryId});
  final int? defaultCategoryId;

  @override
  ConsumerState<PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends ConsumerState<PostComposerSheet> {
  final _contentController = TextEditingController();
  final _client = Supabase.instance.client;

  bool _loading = false;
  String? _error;
  bool _isAnonymous = true;


  ComposerPostType _postType = ComposerPostType.text;
  final List<TextEditingController> _pollOptionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void initState() {
    super.initState();

    // Preselect category if coming from a category feed
    if (widget.defaultCategoryId != null && widget.defaultCategoryId! > 0) {
      _selectedCategoryId = widget.defaultCategoryId;
      // Name will be resolved once category provider loads.
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    for (final c in _pollOptionCtrls) {
      c.dispose();
    }
    super.dispose();
  }



  Future<void> _pickCategory(List<Map<String, dynamic>> categories) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>?> (
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        final search = TextEditingController();
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            ),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                final q = search.text.trim().toLowerCase();
                final filtered = categories.where((c) {
                  final nm = (c['name'] ?? '').toString().toLowerCase();
                  return q.isEmpty || nm.contains(q);
                }).toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Select category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: search,
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search category…',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final id = c['id'];
                          final name = (c['name'] ?? '').toString();
                          final isSel = _selectedCategoryId != null && _selectedCategoryId == id;
                          return ListTile(
                            leading: Icon(isSel ? Icons.check_circle : Icons.tag),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            onTap: () => Navigator.pop(ctx, c),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _selectedCategoryId = picked['id'] as int?;
      _selectedCategoryName = (picked['name'] ?? '').toString();
    });
  }

  Future<void> _createPost() async {
    if (!mounted) return;

    final remaining = await RateLimitService.checkPostCooldown();
    if (remaining != null) {
      final secs = remaining.inSeconds + 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Slow down 🙂 You can post again in ${secs}s.')),
      );
      return;
    }

    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can\'t post nothing!')),
      );
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category.')),
      );
      return;
    }

    if (_postType == ComposerPostType.poll) {
      final optionTexts = _pollOptionCtrls
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (optionTexts.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least 2 poll options.')),
        );
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = _client.auth.currentUser?.id;
      if (me == null) throw 'You are not logged in.';

      final inserted = await _client
          .from('posts')
          .insert({
            'user_id': me,
            'content': content,
            'anonymous': _isAnonymous,
            'is_deleted': false,
            'is_public': true,
          })
          .select('id')
          .single();

      final postId = (inserted['id'] ?? '').toString();
      if (postId.isEmpty) throw 'Failed to create post.';

      await _client.from('post_categories').insert([
        {'post_id': postId, 'category_id': _selectedCategoryId}
      ]);

      if (_postType == ComposerPostType.poll) {
        final optionTexts = _pollOptionCtrls
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();

        final pollInserted = await _client
            .from('polls')
            .insert({'post_id': postId, 'question': content})
            .select('id')
            .single();

        final pollId = (pollInserted['id'] ?? '').toString();
        if (pollId.isEmpty) throw 'Failed to create poll.';

        // CORRECTED: Column name is 'option_text' in schema
        final optionRows = optionTexts.map((t) => {'poll_id': pollId, 'option_text': t}).toList();
        await _client.from('poll_options').insert(optionRows);
      }

      await RateLimitService.markPosted();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 18,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Create post', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Post type toggle (Text / Poll)
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Text'),
                        selected: _postType == ComposerPostType.text,
                        onSelected: _loading ? null : (_) => setState(() => _postType = ComposerPostType.text),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Poll'),
                        selected: _postType == ComposerPostType.poll,
                        onSelected: _loading ? null : (_) => setState(() => _postType = ComposerPostType.poll),
                      ),
                      const Spacer(),
                      Switch(
                        value: _isAnonymous,
                        onChanged: _loading ? null : (v) => setState(() => _isAnonymous = v),
                      ),
                      Text(_isAnonymous ? 'Anonymous' : 'Named', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),

                  const SizedBox(height: 10),
                  TextField(
                    controller: _contentController,
                    maxLines: _postType == ComposerPostType.poll ? 2 : 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _postType == ComposerPostType.poll
                          ? 'Ask a question for your poll…'
                          : 'What\'s happening? (be kind ✨)',
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  if (_postType == ComposerPostType.poll) ...[
                    const SizedBox(height: 12),
                    const Text('Poll options', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _pollOptionCtrls.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: TextField(
                          controller: _pollOptionCtrls[i],
                          decoration: InputDecoration(
                            hintText: 'Option ${i + 1}',
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _loading || _pollOptionCtrls.length >= 6
                              ? null
                              : () => setState(() => _pollOptionCtrls.add(TextEditingController())),
                          icon: const Icon(Icons.add),
                          label: const Text('Add option'),
                        ),
                        const Spacer(),
                        if (_pollOptionCtrls.length > 2)
                          TextButton.icon(
                            onPressed: _loading
                                ? null
                                : () {
                                    setState(() {
                                      final c = _pollOptionCtrls.removeLast();
                                      c.dispose();
                                    });
                                  },
                            icon: const Icon(Icons.remove),
                            label: const Text('Remove'),
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  const SizedBox(height: 6),

                  // Category selector
                  categoriesAsync.when(
                    data: (cats) {
                      // Update name if default selected
                      if (_selectedCategoryId != null && _selectedCategoryName == 'Select category') {
                        final match = cats.firstWhere(
                          (c) => c['id'] == _selectedCategoryId,
                          orElse: () => <String, dynamic>{},
                        );
                        final nm = (match['name'] ?? '').toString();
                        if (nm.isNotEmpty) _selectedCategoryName = nm;
                      }

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.tag),
                        title: const Text('Category', style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(_selectedCategoryName),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _loading ? null : () => _pickCategory(cats),
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                    error: (e, st) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text('Failed to load categories: $e',
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _loading ? null : _createPost,
                      child: const Text('Post', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Center(child: CircularProgressIndicator()),
                    ),

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
