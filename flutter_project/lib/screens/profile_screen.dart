import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/user_profile_provider.dart';
import '../services/follow_service.dart';
import '../utils/avatar.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'moderator_queue_screen.dart';
import 'saved_posts_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final client = Supabase.instance.client;

    try {
      await client.auth.signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
      return;
    }

    // Make sure we clear any cached providers too.
    ref.invalidate(userProfileProvider);

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfile = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => _signOut(context, ref),
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
          final profileId = (profile['id'] ?? '').toString();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(userProfileProvider.future),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              children: [
                _ProfileHeader(
                  avatarUrl: avatarUrl,
                  displayName: displayName,
                  tagline: tagline,
                  location: location,
                  postCount: postCount,
                  userId: profileId,
                ),
                const Divider(height: 32, indent: 16, endIndent: 16),
                _ProfileInfo(profile: profile),
                const SizedBox(height: 24),
                if (profileId.isNotEmpty) ...[
                  _PendingFollowRequests(userId: profileId),
                  const SizedBox(height: 24),
                ],

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

                const SizedBox(height: 12),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SavedPostsScreen()),
                        );
                      },
                      icon: const Icon(Icons.bookmark_border),
                      label: const Text('Saved posts'),
                    ),
                  ),
                ),

                if ((profile['is_moderator'] == true) || (profile['role']?.toString() == 'moderator')) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ModeratorQueueScreen()),
                          );
                        },
                        icon: const Icon(Icons.shield_outlined),
                        label: const Text('Moderator queue'),
                      ),
                    ),
                  ),
                ],
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
    this.userId,
  });

  final String? avatarUrl;
  final String displayName;
  final String? tagline;
  final String? location;
  final int postCount;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final avatarImage = safeNetworkImageProvider(avatarUrl);

    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: colorScheme.surfaceVariant,
          backgroundImage: avatarImage,
          child: avatarImage == null
              ? Icon(Icons.person, size: 50, color: colorScheme.onSurfaceVariant)
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          displayName,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
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
            _FollowStatColumn(userId: userId, label: 'Followers', type: _FollowStatType.followers),
            _FollowStatColumn(userId: userId, label: 'Following', type: _FollowStatType.following),
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
          Text(
            'Contact Information',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
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
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

enum _FollowStatType { followers, following }

class _FollowStatColumn extends StatelessWidget {
  const _FollowStatColumn({required this.userId, required this.label, required this.type});

  final String? userId;
  final String label;
  final _FollowStatType type;

  @override
  Widget build(BuildContext context) {
    if (userId == null || userId!.isEmpty) {
      return _StatColumn(label: label, value: '0');
    }

    return FutureBuilder<FollowStats>(
      future: FollowService.statsForUser(userId!),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        final value = type == _FollowStatType.followers ? stats?.followers : stats?.following;
        return _StatColumn(label: label, value: (value ?? 0).toString());
      },
    );
  }
}

class _PendingFollowRequests extends StatefulWidget {
  const _PendingFollowRequests({required this.userId});

  final String userId;

  @override
  State<_PendingFollowRequests> createState() => _PendingFollowRequestsState();
}

class _PendingFollowRequestsState extends State<_PendingFollowRequests> {
  late Future<List<FollowRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = FollowService.pendingRequestsForMe();
  }

  void _reload() {
    setState(() => _future = FollowService.pendingRequestsForMe());
  }

  Future<void> _decide(FollowRequest request, bool approve) async {
    try {
      await FollowService.decideRequest(requestId: request.id, approve: approve);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'Follow request approved.' : 'Follow request declined.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update request: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FollowRequest>>(
      future: _future,
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const <FollowRequest>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: LinearProgressIndicator(),
          );
        }
        if (requests.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Follow Requests',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...requests.map(
                (request) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1)),
                    title: Text(request.followerName),
                    subtitle: const Text('Wants to follow you'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => _decide(request, false),
                          child: const Text('Decline'),
                        ),
                        ElevatedButton(
                          onPressed: () => _decide(request, true),
                          child: const Text('Approve'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late Future<void> _future;
  Map<String, dynamic>? _profile;
  String _followStatus = 'none';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final profile = await FollowService.profileForUserId(widget.userId);
    final profileId = (profile?['id'] ?? '').toString();
    final status = profileId.isEmpty ? 'none' : await FollowService.statusForTarget(profileId);
    _profile = profile;
    _followStatus = status;
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _requestFollow(String profileId) async {
    try {
      await FollowService.requestFollow(profileId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow request sent. Waiting for approval.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send follow request: $e')),
      );
    }
  }

  Future<void> _cancelFollow(String profileId) async {
    try {
      await FollowService.unfollowOrCancel(profileId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_followStatus == 'approved' ? 'Unfollowed user.' : 'Follow request cancelled.')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = _profile;
          if (profile == null) {
            return const Center(child: Text('Could not load this profile.'));
          }

          final profileId = (profile['id'] ?? '').toString();
          final avatarUrl = profile['avatar_url']?.toString();
          final displayName = (profile['display_name'] ?? profile['username'] ?? 'User').toString();
          final tagline = profile['tagline'] as String?;
          final location = profile['location'] as String?;
          final postCount = profile['post_count'] ?? 0;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              children: [
                _ProfileHeader(
                  avatarUrl: avatarUrl,
                  displayName: displayName,
                  tagline: tagline,
                  location: location,
                  postCount: postCount is int ? postCount : int.tryParse(postCount.toString()) ?? 0,
                  userId: profileId,
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _FollowButton(
                    status: _followStatus,
                    onFollow: () => _requestFollow(profileId),
                    onCancel: () => _cancelFollow(profileId),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.status, required this.onFollow, required this.onCancel});

  final String status;
  final VoidCallback onFollow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (status == 'self') return const SizedBox.shrink();
    if (status == 'approved') {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.person_remove_outlined),
          label: const Text('Following'),
        ),
      );
    }
    if (status == 'pending') {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.hourglass_top),
          label: const Text('Requested - Waiting for Approval'),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onFollow,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Request to Follow'),
      ),
    );
  }
}
