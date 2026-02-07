import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/user_profile_provider.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfile = ref.watch(userProfileProvider);
    final client = Supabase.instance.client;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await client.auth.signOut();
            },
          ),
        ],
      ),
      body: userProfile.when(
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Could not load profile.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(userProfileProvider),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            );
          }
          
          final avatarUrl = profile['avatar_url'];
          final displayName = profile['display_name'] ?? 'No Name';
          final tagline = profile['tagline'];
          final location = profile['location'];
          final postCount = profile['post_count'] ?? 0;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(userProfileProvider.future),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              children: [
                _ProfileHeader(avatarUrl: avatarUrl, displayName: displayName, tagline: tagline, location: location, postCount: postCount),
                const Divider(height: 32, indent: 16, endIndent: 16),
                _ProfileInfo(profile: profile),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                        );
                      },
                      child: const Text('Edit Profile'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('An error occurred: $err')),
      ),
    );
  }
}

// --- UI Helper Widgets ---

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    this.avatarUrl,
    required this.displayName,
    this.tagline,
    this.location,
    required this.postCount,
  });

  final String? avatarUrl;
  final String displayName;
  final String? tagline;
  final String? location;
  final int postCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: colorScheme.surfaceVariant,
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
          child: avatarUrl == null ? Icon(Icons.person, size: 50, color: colorScheme.onSurfaceVariant) : null,
        ),
        const SizedBox(height: 16),
        Text(displayName, style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        if (tagline != null && tagline!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(tagline!, style: textTheme.bodyLarge, textAlign: TextAlign.center),
          ),
        if (location != null && location!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: textTheme.bodySmall?.color),
                const SizedBox(width: 4),
                Text(location!, style: textTheme.bodySmall),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatColumn(label: 'Posts', value: postCount.toString()),
            _StatColumn(label: 'Followers', value: '0'), 
            _StatColumn(label: 'Following', value: '0'),
          ],
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }
}

class _ProfileInfo extends StatelessWidget {
  const _ProfileInfo({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final email = profile['email'] ?? 'Not available';
    final phone = profile['phone_number'] ?? 'Not available';
    final dob = profile['date_of_birth'] ?? 'Not available';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contact Information', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.email_outlined, label: 'Email', value: email),
          const Divider(),
          _InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: phone),
          const Divider(),
          _InfoRow(icon: Icons.cake_outlined, label: 'Born', value: dob),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[700]),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value, style: TextStyle(color: Colors.grey[800])),
        ],
      ),
    );
  }
}
