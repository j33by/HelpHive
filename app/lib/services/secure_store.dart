import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _key = 'helphive.session';
const _vault = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

/// Keeps the Supabase session in the Android keystore-backed store
/// instead of plain shared preferences.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _vault.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _vault.read(key: _key);

  @override
  Future<void> removePersistedSession() => _vault.delete(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _vault.write(key: _key, value: persistSessionString);
}
