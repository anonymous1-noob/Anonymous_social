import 'local_prefs.dart';

/// Simple client-side cooldowns to reduce spam.
///
/// This is NOT security (users can bypass), but it significantly improves UX.
/// Pair it later with server-side rate limits / RLS + edge functions.
class RateLimitService {
  static const _kLastPostAt = 'rl_last_post_at_ms';
  static const _kLastCommentAt = 'rl_last_comment_at_ms';

  static Future<int> _nowMs() async => DateTime.now().millisecondsSinceEpoch;

  static Future<Duration?> checkPostCooldown({Duration cooldown = const Duration(seconds: 30)}) async {
    final prefs = await LocalPrefs.instance();
    final last = prefs.getInt(_kLastPostAt) ?? 0;
    final now = await _nowMs();
    final diff = now - last;
    final remaining = cooldown.inMilliseconds - diff;
    if (remaining <= 0) return null;
    return Duration(milliseconds: remaining);
  }

  static Future<void> markPosted() async {
    final prefs = await LocalPrefs.instance();
    await prefs.setInt(_kLastPostAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<Duration?> checkCommentCooldown({Duration cooldown = const Duration(seconds: 8)}) async {
    final prefs = await LocalPrefs.instance();
    final last = prefs.getInt(_kLastCommentAt) ?? 0;
    final now = await _nowMs();
    final diff = now - last;
    final remaining = cooldown.inMilliseconds - diff;
    if (remaining <= 0) return null;
    return Duration(milliseconds: remaining);
  }

  static Future<void> markCommented() async {
    final prefs = await LocalPrefs.instance();
    await prefs.setInt(_kLastCommentAt, DateTime.now().millisecondsSinceEpoch);
  }
}
