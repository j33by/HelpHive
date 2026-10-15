import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _key = 'helphive.session';
const _vault = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

/// Keeps the Supabase session in the Android keystore-backed store
/// instead of plain shared preferences.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage()
      : super(
          initialize: _noop,
          hasAccessToken: _has,
          accessToken: _read,
          removePersistedSession: _remove,
          persistSession: _write,
        );

  static Future<void> _noop() async {}
  static Future<bool> _has() async => (await _vault.containsKey(key: _key));
  static Future<String?> _read() => _vault.read(key: _key);
  static Future<void> _remove() => _vault.delete(key: _key);
  static Future<void> _write(String value) => _vault.write(key: _key, value: value);
}
