import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

class EditPostScreen extends StatefulWidget {
  final Post post;

  const EditPostScreen({super.key, required this.post});

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  final _client = Supabase.instance.client;
  final _contentController = TextEditingController();

  bool _loading = false;
  String? _error;

  final List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  String _selectedCategoryName = 'Select category';

  @override
  void initState() {
    super.initState();
    _contentController.text = widget.post.content;
    _loadMeta();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cats = await _client.from('categories').select('id, name').order('name');
      _categories
        ..clear()
        ..addAll((cats as List).cast<Map<String, dynamic>>());

      try {
        final rows = await _client
            .from('post_categories')
            .select('category_id, categories(name)')
            .eq('post_id', widget.post.id)
            .limit(1);

        if ((rows as List).isNotEmpty) {
          final m = rows.first as Map;
          final cid = m['category_id'];
          if (cid is int) {
            _selectedCategoryId = cid;
          } else if (cid is String) {
            _selectedCategoryId = int.tryParse(cid);
          }

          final cat = m['categories'];
          if (cat is Map) {
            final nm = (cat['name'] ?? '').toString().trim();
            if (nm.isNotEmpty) _selectedCategoryName = nm;
          } else if (_selectedCategoryId != null) {
            final match = _categories.firstWhere(
              (c) => c['id'] == _selectedCategoryId,
              orElse: () => {},
            );
            final nm = (match['name'] ?? '').toString().trim();
            if (nm.isNotEmpty) _selectedCategoryName = nm;
          }
        }
      } catch (_) {
        // ignore per-post category lookup failures
      }
    } on PostgrestException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to load editor.';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickCategory() async {
    final picked = await _searchPick(
      context: context,
      title: 'Select category',
      items: _categories
          .map((c) => _PickItem(id: (c['id'] ?? '').toString(), label: (c['name'] ?? '').toString()))
          .where((x) => x.id.isNotEmpty)
          .toList(),
      allowNone: false,
      noneLabel: '',
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _selectedCategoryId = int.tryParse(picked.id);
      _selectedCategoryName = picked.label;
    });
  }

  Future<void> _updatePost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Update post core fields
      await _client.from('posts').update({
        'content': content,
        'edited_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.post.id);

      // Update category mapping (single selected category)
      if (_selectedCategoryId != null) {
        await _client.from('post_categories').delete().eq('post_id', widget.post.id);
        await _client.from('post_categories').insert({
          'post_id': widget.post.id,
          'category_id': _selectedCategoryId,
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Edit Post'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _updatePost,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 10),

                // Campus + category controls
                Row(
                  children: [
                    Expanded(
                      child: _PickerButton(
                        label: 'Category',
                        value: _selectedCategoryName,
                        icon: Icons.local_offer_outlined,
                        onTap: _loading ? null : _pickCategory,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    controller: _contentController,
                    decoration: const InputDecoration(
                      hintText: 'Update your post…',
                      border: InputBorder.none,
                    ),
                    maxLines: 8,
                    textInputAction: TextInputAction.newline,
                  ),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _updatePost,
                    child: const Text('Save changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _PickerButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickItem {
  final String id;
  final String label;
  const _PickItem({required this.id, required this.label});
}

/// A reusable search picker bottom sheet.
/// Returns:
/// - null if cancelled
/// - _PickItem with id='__NONE__' if "none/public" selected (when allowNone=true)
Future<_PickItem?> _searchPick({
  required BuildContext context,
  required String title,
  required List<_PickItem> items,
  required bool allowNone,
  required String noneLabel,
}) async {
  final controller = TextEditingController();
  return showModalBottomSheet<_PickItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        final q = controller.text.trim().toLowerCase();
        final filtered = items.where((x) => q.isEmpty || x.label.toLowerCase().contains(q)).toList();

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
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
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: (allowNone ? 1 : 0) + filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      if (allowNone && i == 0) {
                        return ListTile(
                          leading: const Icon(Icons.public),
                          title: Text(noneLabel),
                          onTap: () => Navigator.pop(ctx, const _PickItem(id: '__NONE__', label: 'Public')),
                        );
                      }
                      final idx = allowNone ? i - 1 : i;
                      final item = filtered[idx];
                      return ListTile(
                        title: Text(item.label),
                        onTap: () => Navigator.pop(ctx, item),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      });
    },
  );
}
