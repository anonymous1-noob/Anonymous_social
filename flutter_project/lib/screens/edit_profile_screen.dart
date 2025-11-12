import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _avatarUrlController = TextEditingController();
  final _client = Supabase.instance.client;
  List<int> _selectedCategoryIds = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await _client.from('categories').select();
      setState(() {
        _categories = response;
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _loadProfile() async {
    final authId = _client.auth.currentUser?.id;
    if (authId == null) return;

    try {
      final response = await _client
          .from('users')
          .select('display_name, username, avatar_url, user_category(category_id)')
          .eq('auth_id', authId)
          .single();

      setState(() {
        _displayNameController.text = response['display_name'] ?? '';
        _usernameController.text = response['username'] ?? '';
        _avatarUrlController.text = response['avatar_url'] ?? '';
        _selectedCategoryIds = (response['user_category'] as List)
            .map((e) => e['category_id'] as int)
            .toList();
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _loading = true; _error = null; });

    final authId = _client.auth.currentUser?.id;
    if (authId == null) return;

    try {
      await _client.from('users').update({
        'display_name': _displayNameController.text,
        'username': _usernameController.text,
        'avatar_url': _avatarUrlController.text,
      }).eq('auth_id', authId);

      // Get the user's primary key
      final userResponse = await _client.from('users').select('id').eq('auth_id', authId).single();
      final userId = userResponse['id'];

      // Remove all existing user categories
      await _client.from('user_category').delete().eq('user_id', userId);

      // Insert the new user categories
      for (var categoryId in _selectedCategoryIds) {
        await _client.from('user_category').insert({
          'user_id': userId,
          'category_id': categoryId,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile updated!')));
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = 'An unexpected error occurred.'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _displayNameController,
                  decoration: InputDecoration(labelText: 'Display Name'),
                  validator: (value) => value!.isEmpty ? 'Cannot be empty' : null,
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(labelText: 'Username'),
                  validator: (value) => value!.isEmpty ? 'Cannot be empty' : null,
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _avatarUrlController,
                  decoration: InputDecoration(labelText: 'Avatar URL'),
                ),
                SizedBox(height: 12),
                Text('Categories', style: Theme.of(context).textTheme.headlineSmall),
                Wrap(
                  spacing: 8.0,
                  children: _categories.map((category) {
                    final isSelected = _selectedCategoryIds.contains(category['id']);
                    return FilterChip(
                      label: Text(category['name']),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCategoryIds.add(category['id']);
                          } else {
                            _selectedCategoryIds.remove(category['id']);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _updateProfile,
                  child: Text('Update Profile'),
                ),
                if (_loading) CircularProgressIndicator(),
                if (_error != null) Text(_error!, style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
