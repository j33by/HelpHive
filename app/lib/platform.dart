import 'dart:io';

/// True on Windows, macOS and Linux. These builds need no signing key: the
/// session lives in plain app preferences and Google sign-in returns through
/// a loopback address instead of a custom URL scheme.
final bool isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
