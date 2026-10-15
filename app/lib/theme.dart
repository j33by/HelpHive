import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  static const bg = Color(0xFFF5EEE4);
  static const surface = Color(0xFFFBF7F0);
  static const sunken = Color(0xFFEDE3D4);
  static const ink = Color(0xFF3A2E24);
  static const inkSoft = Color(0xFF8A7A6A);
  static const honey = Color(0xFFF2B33D);
  static const honeyDeep = Color(0xFFD9961A);
  static const honeyPale = Color(0xFFFCE9BE);
  static const rose = Color(0xFFD9694F);
  static const sage = Color(0xFF6E9E7D);
  static const shadowDark = Color(0xFFD6C5AE);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.honey, brightness: Brightness.light)
      .copyWith(primary: C.honeyDeep, onPrimary: Colors.white, surface: C.bg, onSurface: C.ink, error: C.rose);
  final text = GoogleFonts.nunitoTextTheme().apply(bodyColor: C.ink, displayColor: C.ink);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: C.ink),
      iconTheme: const IconThemeData(color: C.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      constraints: BoxConstraints(maxWidth: 560),
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.honeyDeep),
  );
}

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message)));
}

String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${mo[t.month - 1]} ${t.day}${t.year == DateTime.now().year ? '' : ', ${t.year}'}';
}
