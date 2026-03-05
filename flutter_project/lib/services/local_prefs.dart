import 'package:shared_preferences/shared_preferences.dart';

/// Small wrapper so we have a single place to manage SharedPreferences.
class LocalPrefs {
  LocalPrefs._();

  static Future<SharedPreferences> instance() => SharedPreferences.getInstance();
}
