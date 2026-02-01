import 'supabase_service.dart';


class AnonIdentity {
final String name;
final String color;
final String seed;


AnonIdentity(this.name, this.color, this.seed);
}


class AnonIdentityService {
static Future<AnonIdentity> getOrCreate(int categoryId) async {
final userId = supabase.auth.currentUser!.id;


final existing = await supabase
.from('user_anonymous_identity')
.select()
.eq('user_id', userId)
.eq('category_id', categoryId)
.maybeSingle();


if (existing != null) {
return AnonIdentity(
existing['anon_name'],
existing['anon_color'],
existing['avatar_seed'],
);
}


final seed = '$userId-$categoryId';


final anon = {
'user_id': userId,
'category_id': categoryId,
'anon_name': _anonName(seed),
'anon_color': _anonColor(seed),
'avatar_seed': seed,
};


await supabase.from('user_anonymous_identity').insert(anon);


return AnonIdentity(anon['anon_name'], anon['anon_color'], seed);
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