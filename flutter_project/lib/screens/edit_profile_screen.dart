import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/user_profile_provider.dart';
import '../utils/avatar.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _client = Supabase.instance.client;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _taglineController = TextEditingController();
  final _locationController = TextEditingController();
  final _dobController = TextEditingController();

  bool _isUpdating = false;
  bool _loadedProfile = false;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _populateForm(ref.read(userProfileProvider).value);
  }

  void _populateForm(Map<String, dynamic>? userProfile) {
    if (_loadedProfile || userProfile == null) return;

    _nameController.text = userProfile['display_name'] ?? '';
    _phoneController.text = userProfile['phone_number'] ?? '';
    _taglineController.text = userProfile['tagline'] ?? '';
    _locationController.text = userProfile['location'] ?? '';
    _dobController.text = userProfile['date_of_birth'] ?? '';
    _loadedProfile = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _taglineController.dispose();
    _locationController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
      maxHeight: 1024,
    );

    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    if (!mounted) return;

    setState(() {
      _selectedImage = pickedFile;
      _selectedImageBytes = bytes;
      _error = null;
    });
  }

  String _contentTypeForImage(XFile image) {
    final source = '${image.name}.${image.path}'.toLowerCase();
    if (source.contains('.png')) return 'image/png';
    if (source.contains('.webp')) return 'image/webp';
    if (source.contains('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _extensionForImage(XFile image) {
    switch (_contentTypeForImage(image)) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'jpg';
    }
  }

  Future<String?> _uploadImage() async {
    final image = _selectedImage;
    final bytes = _selectedImageBytes;
    if (image == null || bytes == null) return null;

    final authId = _client.auth.currentUser?.id;
    if (authId == null) {
      throw AuthException('You must be signed in to update your avatar.');
    }

    final extension = _extensionForImage(image);
    final fileName = '$authId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    final contentType = _contentTypeForImage(image);

    await _client.storage.from('avatars').uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _client.storage.from('avatars').getPublicUrl(fileName);
  }

  Future<void> _updateProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isUpdating = true;
      _error = null;
    });

    try {
      final newAvatarUrl = await _uploadImage();
      final authId = _client.auth.currentUser?.id;
      if (authId == null) {
        throw AuthException('You must be signed in to update your profile.');
      }

      String? emptyToNull(String value) => value.trim().isEmpty ? null : value.trim();

      final updates = {
        'display_name': _nameController.text.trim(),
        'phone_number': emptyToNull(_phoneController.text),
        'tagline': emptyToNull(_taglineController.text),
        'location': emptyToNull(_locationController.text),
        'date_of_birth': emptyToNull(_dobController.text),
        if (newAvatarUrl != null) 'avatar_url': newAvatarUrl,
      };

      await _client.from('users').update(updates).eq('auth_id', authId);

      if (mounted) {
        ref.invalidate(userProfileProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated!')),
        );
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not update profile: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(userProfileProvider);
    _populateForm(userProfile.value);

    final avatarUrl = userProfile.value?['avatar_url'];
    final avatarImage = safeNetworkImageProvider(avatarUrl);
    final ImageProvider? selectedAvatarImage = _selectedImageBytes == null
        ? null
        : MemoryImage(_selectedImageBytes!);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundImage: selectedAvatarImage ?? avatarImage,
                          child: (selectedAvatarImage == null && avatarImage == null)
                              ? const Icon(Icons.person, size: 50)
                              : null,
                        ),
                        CircleAvatar(
                          radius: 18,
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt, size: 18),
                            tooltip: 'Choose profile avatar',
                            onPressed: _isUpdating ? null : _pickImage,
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(_selectedImage == null ? 'Add avatar photo' : 'Change avatar photo'),
                      onPressed: _isUpdating ? null : _pickImage,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => (value?.trim().isEmpty ?? true) ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone Number (Optional)')),
              const SizedBox(height: 12),
              TextFormField(controller: _taglineController, decoration: const InputDecoration(labelText: 'Tagline / Bio (Optional)')),
              const SizedBox(height: 12),
              TextFormField(controller: _locationController, decoration: const InputDecoration(labelText: 'Location (Optional)')),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dobController,
                decoration: const InputDecoration(labelText: 'Date of Birth (Optional)'),
                readOnly: true,
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _dobController.text.isNotEmpty
                        ? DateTime.tryParse(_dobController.text) ?? DateTime.now()
                        : DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    _dobController.text = pickedDate.toIso8601String().substring(0, 10);
                  }
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUpdating ? null : _updateProfile,
                  child: const Text('Update Profile'),
                ),
              ),
              if (_isUpdating)
                const Padding(
                  padding: EdgeInsets.only(top: 16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
