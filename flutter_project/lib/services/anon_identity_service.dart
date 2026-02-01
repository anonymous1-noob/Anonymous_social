import 'supabase_service.dart';

/// Anonymous identity per (user_id, category_id).
///
/// IMPORTANT (project consistency):
/// - This service uses auth user id (supabase.auth.currentUser!.id) as `user_id`.
/// - It also uses the column name `color_hex` (not `anon_color`).
///
/// Make sure your DB schema matches these names:
/// table: user_anonymous_identity
/// columns: user_id (uuid), category_id (int), anon_name (text), color_hex (text), avatar_seed (text)
class AnonIdentity {
  final String name;
  final String colorHex;
  final String seed;

  const AnonIdentity(this.name, this.colorHex, this.seed);
}

class AnonIdentityService {
  static Future<AnonIdentity> getOrCreate(int categoryId) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not authenticated');
    }

    final userId = user.id;

    // Try fetch
    final existing = await supabase
        .from('user_anonymous_identity')
        .select('user_id, category_id, anon_name, color_hex, avatar_seed')
        .eq('user_id', userId)
        .eq('category_id', categoryId)
        .maybeSingle();

    if (existing != null) {
      final name = (existing['anon_name'] ?? '').toString();
      final colorHex = (existing['color_hex'] ?? '').toString();
      final seed = (existing['avatar_seed'] ?? '').toString();
      return AnonIdentity(name, colorHex, seed);
    }

    // Create
    final seed = '$userId-$categoryId';
    final anon = <String, dynamic>{
      'user_id': userId,
      'category_id': categoryId,
      'anon_name': _anonName(seed),
      'color_hex': _anonColor(seed),
      'avatar_seed': seed,
    };

    await supabase.from('user_anonymous_identity').insert(anon);

    return AnonIdentity(
      (anon['anon_name'] ?? '').toString(),
      (anon['color_hex'] ?? '').toString(),
      seed,
    );
  }

  static String _anonName(String seed) {
    const animals = ['Fox', 'Wolf', 'Otter', 'Hawk', 'Tiger'];
    const colors = ['Blue', 'Red', 'Green', 'Purple', 'Orange'];
    final i = seed.hashCode.abs();
    return '${colors[i % colors.length]} ${animals[i % animals.length]}';
  }

  static String _anonColor(String seed) {
    const palette = ['#FF6B6B', '#4ECDC4', '#556270', '#C7F464'];
    return palette[seed.hashCode.abs() % palette.length];
  }
}

class AuthException {
  final String message;
  const AuthException(this.message);
}
