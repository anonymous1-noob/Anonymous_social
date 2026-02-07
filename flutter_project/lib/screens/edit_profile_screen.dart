import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

import '../providers/user_profile_provider.dart';

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
  File? _selectedImage;
  String? _error;

  @override
  void initState() {
    super.initState();
    final userProfile = ref.read(userProfileProvider).value;
    if (userProfile != null) {
      _nameController.text = userProfile['display_name'] ?? '';
      _phoneController.text = userProfile['phone_number'] ?? '';
      _taglineController.text = userProfile['tagline'] ?? '';
      _locationController.text = userProfile['location'] ?? '';
      _dobController.text = userProfile['date_of_birth'] ?? '';
    }
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
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;
    final authId = _client.auth.currentUser!.id;
    final fileName = '${authId}/${DateTime.now().millisecondsSinceEpoch}.png';
    
    await _client.storage.from('avatars').upload(fileName, _selectedImage!);
    return _client.storage.from('avatars').getPublicUrl(fileName);
  }

  Future<void> _updateProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() { _isUpdating = true; _error = null; });

    try {
      String? newAvatarUrl = await _uploadImage();
      final authId = _client.auth.currentUser!.id;

      String? _emptyToNull(String value) => value.trim().isEmpty ? null : value.trim();

      final updates = {
        'display_name': _nameController.text,
        'phone_number': _emptyToNull(_phoneController.text),
        'tagline': _emptyToNull(_taglineController.text),
        'location': _emptyToNull(_locationController.text),
        'date_of_birth': _emptyToNull(_dobController.text),
        if (newAvatarUrl != null) 'avatar_url': newAvatarUrl,
      };

      await _client.from('users').update(updates).eq('auth_id', authId);

      if (mounted) {
        // CRITICAL FIX: Invalidate the provider to force a refresh.
        ref.invalidate(userProfileProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile updated!')));
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = 'An unexpected error occurred.'; });
    } finally {
      if (mounted) {
        setState(() { _isUpdating = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(userProfileProvider);
    final avatarUrl = userProfile.value?['avatar_url'];

    return Scaffold(
      appBar: AppBar(title: Text('Edit Profile')),
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
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: _selectedImage != null 
                          ? FileImage(_selectedImage!) 
                          : (avatarUrl != null ? NetworkImage(avatarUrl) : null) as ImageProvider?,
                      child: (avatarUrl == null && _selectedImage == null) ? Icon(Icons.person, size: 50) : null,
                    ),
                    TextButton.icon(
                      icon: Icon(Icons.camera_alt),
                      label: Text('Change Photo'),
                      onPressed: _pickImage,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: 'Name'),
                validator: (value) => (value?.isEmpty ?? true) ? 'Please enter a name' : null,
              ),
              SizedBox(height: 12),
              TextFormField(controller: _phoneController, decoration: InputDecoration(labelText: 'Phone Number (Optional)')),
              SizedBox(height: 12),
              TextFormField(controller: _taglineController, decoration: InputDecoration(labelText: 'Tagline / Bio (Optional)')),
              SizedBox(height: 12),
              TextFormField(controller: _locationController, decoration: InputDecoration(labelText: 'Location (Optional)')),
              SizedBox(height: 12),
              TextFormField(
                controller: _dobController,
                decoration: InputDecoration(labelText: 'Date of Birth (Optional)'),
                readOnly: true,
                onTap: () async {
                  DateTime? pickedDate = await showDatePicker(
                    context: context, 
                    initialDate: _dobController.text.isNotEmpty ? DateTime.tryParse(_dobController.text) ?? DateTime.now() : DateTime.now(), 
                    firstDate: DateTime(1900), 
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    _dobController.text = pickedDate.toIso8601String().substring(0, 10);
                  }
                },
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: _isUpdating ? null : _updateProfile, child: Text('Update Profile')),
              ),
              if (_isUpdating) Padding(padding: const EdgeInsets.only(top: 16.0), child: Center(child: CircularProgressIndicator())),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_error!, style: TextStyle(color: Colors.red))),
            ],
          ),
        ),
      ),
    );
  }
}
