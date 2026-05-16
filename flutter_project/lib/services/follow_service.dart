import 'package:supabase_flutter/supabase_flutter.dart';

class FollowStats {
  const FollowStats({required this.followers, required this.following});

  final int followers;
  final int following;
}

class FollowRequest {
  const FollowRequest({
    required this.id,
    required this.followerId,
    required this.followerName,
  });

  final String id;
  final String followerId;
  final String followerName;
}

class FollowService {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<String?> currentPublicUserId() async {
    final authId = _client.auth.currentUser?.id;
    if (authId == null) return null;

    final row = await _client
        .from('users')
        .select('id')
        .eq('auth_id', authId)
        .maybeSingle();
    final id = (row?['id'] ?? '').toString();
    return id.isEmpty ? authId : id;
  }

  static Future<Map<String, dynamic>?> profileForUserId(String userId) async {
    if (userId.trim().isEmpty) return null;

    final rows = await _client
        .from('users')
        .select('*')
        .or('id.eq.$userId,auth_id.eq.$userId')
        .limit(1);

    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  static Future<FollowStats> statsForUser(String userId) async {
    final followers = await _client
        .from('user_follows')
        .select('id')
        .eq('following_id', userId)
        .eq('status', 'approved')
        .count(CountOption.exact);

    final following = await _client
        .from('user_follows')
        .select('id')
        .eq('follower_id', userId)
        .eq('status', 'approved')
        .count(CountOption.exact);

    return FollowStats(
      followers: followers.count,
      following: following.count,
    );
  }

  static Future<String> statusForTarget(String targetUserId) async {
    final me = await currentPublicUserId();
    if (me == null) return 'none';
    if (me == targetUserId) return 'self';

    final row = await _client
        .from('user_follows')
        .select('status')
        .eq('follower_id', me)
        .eq('following_id', targetUserId)
        .maybeSingle();

    return (row?['status'] ?? 'none').toString();
  }

  static Future<void> requestFollow(String targetUserId) async {
    final me = await currentPublicUserId();
    if (me == null) throw 'You are not logged in.';
    if (me == targetUserId) throw 'You cannot follow yourself.';

    await _client.from('user_follows').upsert(
      {
        'follower_id': me,
        'following_id': targetUserId,
        'status': 'pending',
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'follower_id,following_id',
    );
  }

  static Future<void> unfollowOrCancel(String targetUserId) async {
    final me = await currentPublicUserId();
    if (me == null) throw 'You are not logged in.';

    await _client.from('user_follows').delete().match({
      'follower_id': me,
      'following_id': targetUserId,
    });
  }

  static Future<List<FollowRequest>> pendingRequestsForMe() async {
    final me = await currentPublicUserId();
    if (me == null) return const [];

    final rows = await _client
        .from('user_follows')
        .select('id, follower_id')
        .eq('following_id', me)
        .eq('status', 'pending')
        .order('requested_at', ascending: false);

    final followerIds = rows
        .map<String>((row) => ((row as Map)['follower_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final namesById = <String, String>{};
    if (followerIds.isNotEmpty) {
      final users = await _client
          .from('users')
          .select('id, display_name, username')
          .inFilter('id', followerIds);

      for (final userRow in users) {
        final user = Map<String, dynamic>.from(userRow as Map);
        final id = (user['id'] ?? '').toString();
        final name = (user['display_name'] ?? user['username'] ?? '').toString().trim();
        if (id.isNotEmpty && name.isNotEmpty) namesById[id] = name;
      }
    }

    return rows.map<FollowRequest>((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final followerId = (map['follower_id'] ?? '').toString();
      return FollowRequest(
        id: (map['id'] ?? '').toString(),
        followerId: followerId,
        followerName: namesById[followerId] ?? 'User',
      );
    }).toList();
  }

  static Future<void> decideRequest({required String requestId, required bool approve}) async {
    final me = await currentPublicUserId();
    if (me == null) throw 'You are not logged in.';

    if (approve) {
      await _client.from('user_follows').update({
        'status': 'approved',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }).match({'id': requestId, 'following_id': me});
    } else {
      await _client.from('user_follows').delete().match({
        'id': requestId,
        'following_id': me,
      });
    }
  }
}
