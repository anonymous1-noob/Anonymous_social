import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> showPostComposerSheet({
  required BuildContext context,
  required int categoryId,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: _PostComposerSheet(categoryId: categoryId),
      );
    },
  );
}

class _PostComposerSheet extends StatefulWidget {
  final int categoryId;
  const _PostComposerSheet({required this.categoryId});

  @override
  State<_PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<_PostComposerSheet> {
  final _supabase = Supabase.instance.client;

  final _captionController = TextEditingController();
  bool _posting = false;

  // Image state
  XFile? _pickedFile;
  Uint8List? _pickedBytes;
  String? _pickedExt;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();
      final ext = _inferExt(file.name);

      setState(() {
        _pickedFile = file;
        _pickedBytes = bytes;
        _pickedExt = ext;
      });
    } catch (e, st) {
      debugPrint('PICK IMAGE ERROR: $e');
      debugPrint('$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image pick failed: $e')),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _pickedFile = null;
      _pickedBytes = null;
      _pickedExt = null;
    });
  }

  String _inferExt(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.jpeg')) return 'jpeg';
    if (lower.endsWith('.jpg')) return 'jpg';
    if (lower.endsWith('.gif')) return 'gif';
    return 'jpg';
  }

  String _contentTypeForExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _ensureAnonIdentity(String userId) async {
    try {
      await _supabase.rpc('ensure_anon_identity', params: {'p_user_id': userId});
    } catch (_) {
      // ignore
    }
  }

  Future<void> _submit() async {
    if (_posting) return;

    final user = _supabase.auth.currentUser;
    debugPrint('UPLOAD currentUser: ${user?.id}');
    debugPrint('UPLOAD accessToken null? ${_supabase.auth.currentSession?.accessToken == null}');

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login before posting.')),
      );
      return;
    }

    final caption = _captionController.text.trim();
    final hasImage = _pickedBytes != null;

    if (caption.isEmpty && !hasImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something or add a photo.')),
      );
      return;
    }

    if (widget.categoryId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid category. Please select a valid category.')),
      );
      return;
    }

    setState(() => _posting = true);

    try {
      await _ensureAnonIdentity(user.id);

      String? mediaUrl;
      String? mediaPath;

      if (hasImage) {
        final bucket = 'post_media';
        final ext = _pickedExt ?? 'jpg';
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
        mediaPath = '${user.id}/$fileName';

        debugPrint('UPLOAD media path: $mediaPath');

        await _supabase.storage.from(bucket).uploadBinary(
              mediaPath,
              _pickedBytes!,
              fileOptions: FileOptions(
                upsert: false, // important: avoid needing UPDATE policy
                contentType: _contentTypeForExt(ext),
              ),
            );

        mediaUrl = _supabase.storage.from(bucket).getPublicUrl(mediaPath);
      }

      await _supabase.from('posts').insert({
        'user_id': user.id,
        'category_id': widget.categoryId,
        'content': caption,
        'is_deleted': false,
        'media_url': mediaUrl,
        'media_path': mediaPath,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posted ✅')),
      );
    } catch (e, st) {
      debugPrint('POST ERROR: $e');
      debugPrint('$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPost = !_posting &&
        (_captionController.text.trim().isNotEmpty || _pickedBytes != null);

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
                      onPressed: _posting ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      splashRadius: 18,
                    ),
                    const Spacer(),
                    const Text(
                      'New post',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: canPost ? _submit : null,
                      child: _posting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Share',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
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
                      controller: _captionController,
                      onChanged: (_) => setState(() {}),
                      maxLines: null,
                      minLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Write a caption…',
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_pickedBytes == null) ...[
                      InkWell(
                        onTap: _posting ? null : _pickImage,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: const Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined),
                                SizedBox(width: 10),
                                Text(
                                  'Add a photo',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: Image.memory(
                                _pickedBytes!,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Material(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(999),
                                child: InkWell(
                                  onTap: _posting ? null : _removeImage,
                                  borderRadius: BorderRadius.circular(999),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.close,
                                        color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        kIsWeb
                            ? 'Selected image (web)'
                            : 'Selected image: ${_pickedFile?.name ?? ''}',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
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
