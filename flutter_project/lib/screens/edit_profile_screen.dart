import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A screen that allows the currently logged-in user to edit their profile.
///
/// Users can update their display name, username, and avatar URL. They can also
/// modify their selected categories. The screen handles loading the initial state,
/// updating the database, and providing feedback to the user.
class EditProfileScreen extends StatefulWidget {
  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _client = Supabase.instance.client;

  // --- Text Field Controllers ---
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _avatarUrlController = TextEditingController();

  // --- State Variables ---
  bool _loading = false; // Controls the visibility of the loading indicator.
  String? _error; // Holds any error message to be displayed.
  List<Map<String, dynamic>> _categories = []; // Holds all available categories from the database.
  List<int> _initialCategoryIds = []; // Stores the user's categories when the screen first loads to compare against changes.
  List<int> _selectedCategoryIds = []; // Stores the current state of the user's category selections in the UI.

  @override
  void initState() {
    super.initState();
    // When the screen loads, fetch all necessary data to populate the form.
    _loadInitialData();
  }

  @override
  void dispose() {
    // Always dispose of controllers to free up resources.
    _displayNameController.dispose();
    _usernameController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  /// Fetches all necessary data from the database in a safe order.
  Future<void> _loadInitialData() async {
    setState(() { _loading = true; });

    // It's better to fetch all possible categories first.
    await _fetchCategories();
    // Then, fetch the user's specific profile details.
    await _loadUserProfile();

    if (mounted) {
      setState(() { _loading = false; });
    }
  }

  /// Fetches the list of all available categories.
  Future<void> _fetchCategories() async {
    try {
      final response = await _client.from('categories').select('id, name');
      if (mounted) {
        setState(() {
          _categories = response;
        });
      }
    } catch (e) {
      // Handle error, e.g., by showing a snackbar.
    }
  }

  /// Loads the current user's profile data and their associated categories.
  Future<void> _loadUserProfile() async {
    final authId = _client.auth.currentUser?.id;
    if (authId == null) return;

    try {
      // Fetch the user's profile and a list of their joined categories in a single query.
      final response = await _client
          .from('users')
          .select('id, display_name, username, avatar_url, user_category(category_id)')
          .eq('auth_id', authId)
          .single();

      if (mounted) {
        setState(() {
          // Populate the text fields with the fetched data.
          _displayNameController.text = response['display_name'] ?? '';
          _usernameController.text = response['username'] ?? '';
          _avatarUrlController.text = response['avatar_url'] ?? '';
          
          // Extract the category IDs from the nested `user_category` data.
          final categoryIds = (response['user_category'] as List)
              .map((e) => e['category_id'] as int)
              .toList();
          // Store the initial state to track changes, and set the current selection.
          _initialCategoryIds = List.from(categoryIds);
          _selectedCategoryIds = List.from(categoryIds);
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  /// Handles the entire profile update process.
  Future<void> _updateProfile() async {
    // First, validate the form to ensure required fields are not empty.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() { _loading = true; _error = null; });

    final authId = _client.auth.currentUser?.id;
    if (authId == null) return;

    try {
      // 1. Update the user's core profile information in the `users` table.
      await _client.from('users').update({
        'display_name': _displayNameController.text,
        'username': _usernameController.text,
        'avatar_url': _avatarUrlController.text,
      }).eq('auth_id', authId);

      // Get the user's primary key (`id`) to update the join table (`user_category`).
      final userResponse = await _client.from('users').select('id').eq('auth_id', authId).single();
      final userId = userResponse['id'];

      // 2. Efficiently calculate which categories to add and which to remove.
      final categoriesToAdd = _selectedCategoryIds.where((id) => !_initialCategoryIds.contains(id)).toList();
      final categoriesToRemove = _initialCategoryIds.where((id) => !_selectedCategoryIds.contains(id)).toList();

      // 3. Perform a bulk insert for all new category associations.
      if (categoriesToAdd.isNotEmpty) {
        final List<Map<String, dynamic>> userCategoryInserts = categoriesToAdd.map((categoryId) => {
          'user_id': userId,
          'category_id': categoryId,
        }).toList();
        await _client.from('user_category').insert(userCategoryInserts);
      }

      // 4. Perform a bulk delete for all removed category associations.
      if (categoriesToRemove.isNotEmpty) {
        await _client.from('user_category').delete().eq('user_id', userId).in_('category_id', categoriesToRemove);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile updated!')));
        Navigator.of(context).pop(); // Go back to the previous screen.
      }
    } on PostgrestException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = 'An unexpected error occurred.'; });
    } finally {
      if (mounted) {
        setState(() { _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Profile')),
      // Show a loading indicator until the initial data has been fetched.
      body: _loading && _categories.isEmpty
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Input Fields ---
                      TextFormField(
                        controller: _displayNameController,
                        decoration: InputDecoration(labelText: 'Display Name', border: OutlineInputBorder()),
                        validator: (value) => (value?.isEmpty ?? true) ? 'Cannot be empty' : null,
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                        validator: (value) => (value?.isEmpty ?? true) ? 'Cannot be empty' : null,
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _avatarUrlController,
                        decoration: InputDecoration(labelText: 'Avatar URL', border: OutlineInputBorder()),
                      ),
                      SizedBox(height: 20),

                      // --- Category Selection ---
                      Text('Your Categories', style: Theme.of(context).textTheme.headlineSmall),
                      SizedBox(height: 8),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: _categories.map((category) {
                          final isSelected = _selectedCategoryIds.contains(category['id']);
                          return FilterChip(
                            label: Text(category['name'] as String),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedCategoryIds.add(category['id'] as int);
                                } else {
                                  _selectedCategoryIds.remove(category['id'] as int);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 20),

                      // --- Action Button and Indicators ---
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _updateProfile,
                          child: Text('Update Profile'),
                        ),
                      ),
                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
