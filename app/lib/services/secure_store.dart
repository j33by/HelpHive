import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../platform.dart';

const _key = 'helphive.session';
const _vault = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

/// Keeps the Supabase session in the platform's safest store that needs no
/// signing key: the Android keystore-backed vault on phones, and the app's
/// own preferences file on Windows, macOS and Linux (the macOS keychain
/// refuses unsigned apps).
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    if (isDesktop) return (await SharedPreferences.getInstance()).containsKey(_key);
    return _vault.containsKey(key: _key);
  }

  @override
  Future<String?> accessToken() async {
    if (isDesktop) return (await SharedPreferences.getInstance()).getString(_key);
    return _vault.read(key: _key);
  }

  @override
  Future<void> removePersistedSession() async {
    if (isDesktop) {
      await (await SharedPreferences.getInstance()).remove(_key);
    } else {
      await _vault.delete(key: _key);
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (isDesktop) {
      await (await SharedPreferences.getInstance()).setString(_key, persistSessionString);
    } else {
      await _vault.write(key: _key, value: persistSessionString);
    }
  }
}
