import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';
import 'config.dart';
import 'platform.dart';
import 'screens/auth.dart';
import 'screens/shell.dart';
import 'services/secure_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!isDesktop) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: C.bg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  }

  if (Config.ready) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: SecureSessionStorage(),
      ),
    );
  }
  runApp(const HelpHiveApp());
}

/// Lets a mouse or trackpad drag-scroll and pull-to-refresh like a finger does.
class _AnyDeviceScroll extends MaterialScrollBehavior {
  const _AnyDeviceScroll();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

class HelpHiveApp extends StatelessWidget {
  const HelpHiveApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HelpHive',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        scrollBehavior: const _AnyDeviceScroll(),
        home: Config.ready ? const Gate() : const SetupNeeded(),
      );
}

/// Shows the sign-in screen or the app, depending on the Supabase session.
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  late final StreamSubscription<AuthState> _sub;
  Session? _session = Supabase.instance.client.auth.currentSession;

  @override
  void initState() {
    super.initState();
    if (_session != null) AppState.I.start();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((e) {
      final was = _session?.user.id;
      final now = e.session?.user.id;
      if (e.event == AuthChangeEvent.signedOut || now == null) {
        AppState.I.stop();
      } else if (was != now) {
        AppState.I.start();
      }
      if (mounted) setState(() => _session = e.session);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _session == null ? const AuthScreen(key: ValueKey('auth')) : const Shell(key: ValueKey('shell')),
    );
  }
}

class SetupNeeded extends StatelessWidget {
  const SetupNeeded({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Image.asset('assets/icons/bee.png', width: 96),
              const SizedBox(height: 20),
              const Text('HelpHive is not configured', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text(
                'This build is missing SUPABASE_URL, SUPABASE_ANON_KEY or API_URL. Add them as --dart-define values (or Codemagic environment variables) and build again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.inkSoft, height: 1.4),
              ),
            ]),
          ),
        ),
      );
}
