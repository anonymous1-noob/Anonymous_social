import 'package:supabase_flutter/supabase_flutter.dart';

class PollOptionItem {
  PollOptionItem({
    required this.id,
    required this.text,
    required this.votes,
  });

  final String id;
  final String text;
  final int votes;
}

class PollBundle {
  PollBundle({
    required this.pollId,
    required this.question,
    required this.options,
    required this.myOptionId,
  });

  final String pollId;
  final String question;
  final List<PollOptionItem> options;
  final String? myOptionId;
}

/// Poll service (minimal, no extra dependencies).
///
/// Recommended tables:
/// - polls(id uuid pk, post_id text/uuid unique, question text)
/// - poll_options(id uuid pk, poll_id uuid fk, option_text text)
/// - poll_votes(id uuid pk, poll_id uuid, option_id uuid, user_id uuid, created_at timestamptz)
///   with UNIQUE(poll_id, user_id)
class PollService {
  PollService._();

  static final SupabaseClient _client = Supabase.instance.client;

  static final Map<String, PollBundle?> _cacheByPostId = {};

  static void clearCache() => _cacheByPostId.clear();

  static Future<PollBundle?> getPollForPost({required String postId}) async {
    if (_cacheByPostId.containsKey(postId)) return _cacheByPostId[postId];

    try {
      final pollRow = await _client
          .from('polls')
          .select('id, question')
          .eq('post_id', postId)
          .maybeSingle();

      if (pollRow == null) {
        _cacheByPostId[postId] = null;
        return null;
      }

      final pollId = (pollRow['id'] ?? '').toString();
      final question = (pollRow['question'] ?? '').toString();
      if (pollId.isEmpty) {
        _cacheByPostId[postId] = null;
        return null;
      }

      final optionsRes = await _client
          .from('poll_options')
          .select('id, option_text')
          .eq('poll_id', pollId)
          .order('created_at', ascending: true);

      final options = (optionsRes as List).cast<Map<String, dynamic>>();

      final votesRes = await _client
          .from('poll_votes')
          .select('option_id, user_id')
          .eq('poll_id', pollId);

      final votes = (votesRes as List).cast<Map<String, dynamic>>();

      final Map<String, int> counts = {};
      for (final v in votes) {
        final oid = (v['option_id'] ?? '').toString();
        if (oid.isEmpty) continue;
        counts[oid] = (counts[oid] ?? 0) + 1;
      }

      final me = _client.auth.currentUser?.id;
      String? myOptionId;
      if (me != null) {
        for (final v in votes) {
          final uid = (v['user_id'] ?? '').toString();
          if (uid == me) {
            myOptionId = (v['option_id'] ?? '').toString();
            break;
          }
        }
      }

      final items = options
          .map((o) {
            final id = (o['id'] ?? '').toString();
            final text = (o['option_text'] ?? '').toString();
            return PollOptionItem(id: id, text: text, votes: counts[id] ?? 0);
          })
          .where((o) => o.id.isNotEmpty)
          .toList();

      final bundle = PollBundle(
        pollId: pollId,
        question: question,
        options: items,
        myOptionId: myOptionId,
      );

      _cacheByPostId[postId] = bundle;
      return bundle;
    } on PostgrestException {
      _cacheByPostId[postId] = null;
      return null;
    } catch (_) {
      _cacheByPostId[postId] = null;
      return null;
    }
  }

  static Future<void> vote({required String pollId, required String optionId}) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw 'Not logged in';

    // Upsert with unique(poll_id, user_id).
    await _client.from('poll_votes').upsert(
      {
        'poll_id': pollId,
        'option_id': optionId,
        'user_id': me,
      },
      onConflict: 'poll_id,user_id',
    );

    // Best-effort cache bust.
    _cacheByPostId.clear();
  }
}
