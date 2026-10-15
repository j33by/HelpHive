import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

/// Windows, macOS and Linux cannot register the io.helphive.app:// link without
/// an installer or a signed bundle, so Google sign-in comes back to a tiny
/// web server on this machine instead. Add this exact URL under
/// Supabase > Authentication > URL Configuration > Redirect URLs.
const desktopOAuthPort = 47321;
const desktopRedirect = 'http://127.0.0.1:$desktopOAuthPort/login-callback';

Future<void> signInWithGoogleDesktop(SupabaseClient sb) async {
  final HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, desktopOAuthPort);
  } on SocketException {
    throw AuthException('Port $desktopOAuthPort is busy. Close other HelpHive windows and try again.');
  }
  try {
    final res = await sb.auth.getOAuthSignInUrl(provider: OAuthProvider.google, redirectTo: desktopRedirect);
    final opened = await launchUrl(Uri.parse(res.url), mode: LaunchMode.externalApplication);
    if (!opened) throw AuthException('Could not open your browser.');
    final code = await _waitForCode(server).timeout(const Duration(minutes: 3));
    await sb.auth.exchangeCodeForSession(code);
  } on TimeoutException {
    throw AuthException('Google sign-in took too long. Please try again.');
  } finally {
    await server.close(force: true);
  }
}

Future<String> _waitForCode(HttpServer server) async {
  await for (final req in server) {
    if (req.uri.path != '/login-callback') {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      continue;
    }
    final code = req.uri.queryParameters['code'];
    final err = req.uri.queryParameters['error_description'] ?? req.uri.queryParameters['error'];
    final ok = code != null && err == null;
    req.response.headers.contentType = ContentType.html;
    req.response.write(_page(ok));
    await req.response.close();
    if (ok) return code;
    throw AuthException(err ?? 'Google sign-in was cancelled.');
  }
  throw AuthException('Google sign-in was cancelled.');
}

String _page(bool ok) => '''<!doctype html><html><head><meta charset="utf-8"><title>HelpHive</title>
<style>body{font-family:system-ui,sans-serif;background:#F5EEE4;color:#3A2E24;display:grid;place-items:center;height:100vh;margin:0}
div{text-align:center}h1{font-size:22px}p{color:#7A6A5C}</style></head>
<body><div><h1>${ok ? 'You are signed in' : 'Sign-in did not finish'}</h1>
<p>${ok ? 'You can close this tab and go back to HelpHive.' : 'Go back to HelpHive and try again.'}</p></div></body></html>''';
