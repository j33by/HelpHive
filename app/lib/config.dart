import 'platform.dart';

/// Values are passed at build time, never committed:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_URL=...
/// The anon key is public by design; every table is locked down by row level security.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _api = String.fromEnvironment('API_URL');
  static String get apiUrl => _api.replaceAll(RegExp(r'/+$'), '');

  static const authRedirect = 'io.helphive.app://login-callback/';

  /// Where email links (confirm, reset) send people. Desktop has no custom URL
  /// scheme, so it falls back to the project's Site URL and people sign in by hand.
  static String? get emailRedirect => isDesktop ? null : authRedirect;

  static bool get ready =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty && apiUrl.startsWith('https://');
}
