import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/category_provider.dart';

Future<void> showPostComposerSheet({
  required BuildContext context,
  required int categoryId, // Keep this for now as a default
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
  final List<int> _selectedCategoryIds = [];
  bool _isAnonymous = true;

  @override
  void initState() {
    super.initState();
    // Pre-select the default category passed from the HomeShell, if provided.
    if (widget.defaultCategoryId != null) {
      _selectedCategoryIds.add(widget.defaultCategoryId!);
    }
  }

  Future<void> _createPost() async {
    if (!mounted) return;
    if (_contentController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can\'t post nothing!')),
      );
      return;
    }
    if (_selectedCategoryIds.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one category.')),
      );
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // Use the new RPC function for creating posts with multiple categories.
      await _client.rpc('create_post_with_categories', params: {
        'p_content': _contentController.text,
        'p_anonymous': _isAnonymous,
        'p_category_ids': _selectedCategoryIds,
      });

      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'An unexpected error occurred: ${e.toString()}'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                     IconButton(
                      onPressed: _loading ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      splashRadius: 18,
                    ),
                    const Spacer(),
                    const Text('New Post', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const Spacer(),
                    TextButton(
                      onPressed: _loading ? null : _createPost,
                      child: const Text('Share', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(14),
                  children: [
                    TextField(
                      controller: _contentController,
                      maxLines: null,
                      minLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Write something...',
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Select Categories', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    categoriesAsync.when(
                      data: (categories) {
                        return Wrap(
                          spacing: 8.0,
                          runSpacing: 4.0,
                          children: categories.map((category) {
                            final isSelected = _selectedCategoryIds.contains(category['id']);
                            return FilterChip(
                              label: Text(category['name'] as String),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedCategoryIds.add(category['id'] as int);
                                  } else {
                                    // CORRECTED: Fixed the typo here.
                                    _selectedCategoryIds.remove(category['id'] as int);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => const Text('Could not load categories.'),
                    ),
                     const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Post Anonymously'),
                      value: _isAnonymous,
                      onChanged: (value) => setState(() => _isAnonymous = value),
                      secondary: const Icon(Icons.visibility_off_outlined),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
