import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../platform.dart';
import '../services/data.dart';
import '../services/desktop_oauth.dart';
import '../theme.dart';
import '../widgets/clay.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _signUp = false;
  bool _show = false;
  bool _busy = false;
  bool _googleBusy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      if (_signUp) {
        final res = await sb.auth.signUp(
          email: email,
          password: _pass.text,
          data: {'full_name': _name.text.trim()},
          emailRedirectTo: Config.emailRedirect,
        );
        if (res.session == null && mounted) {
          toast(context, 'Almost there. Check $email for a confirmation link.');
          setState(() => _signUp = false);
        }
      } else {
        await sb.auth.signInWithPassword(email: email, password: _pass.text);
      }
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _googleBusy = true);
    try {
      if (isDesktop) {
        await signInWithGoogleDesktop(sb);
      } else {
        await sb.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Config.authRedirect,
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    } finally {
      // the session arrives through the deep link (phones) or the loopback page (desktop)
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      toast(context, 'Type your email above first.');
      return;
    }
    try {
      await sb.auth.resetPasswordForEmail(email, redirectTo: Config.emailRedirect);
      if (mounted) toast(context, 'If that email has an account, a reset link is on its way.');
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(children: [
                  Image.asset('assets/icons/logo.png', width: 110, height: 110),
                  const SizedBox(height: 8),
                  const Text('HelpHive', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                  const SizedBox(height: 6),
                  const Text('Ask for a hand. Lend one.', style: TextStyle(color: C.inkSoft, fontSize: 15)),
                  const SizedBox(height: 28),
                  ClayCard(
                    padding: const EdgeInsets.all(20),
                    radius: 32,
                    child: Column(children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _signUp
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: ClayField(
                                  controller: _name,
                                  hint: 'Your name',
                                  icon: 'user',
                                  maxLength: 60,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.name],
                                  validator: (v) => (v ?? '').trim().isEmpty ? 'Tell us what to call you' : null,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      ClayField(
                        controller: _email,
                        hint: 'Email',
                        icon: 'mail',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'That email looks off',
                      ),
                      const SizedBox(height: 14),
                      ClayField(
                        controller: _pass,
                        hint: 'Password',
                        icon: 'lock',
                        obscure: !_show,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                        suffix: GestureDetector(
                          onTap: () => setState(() => _show = !_show),
                          child: Padding(padding: const EdgeInsets.all(6), child: HIcon(_show ? 'eye_off' : 'eye', size: 20, color: C.inkSoft)),
                        ),
                        validator: (v) {
                          final s = v ?? '';
                          if (s.isEmpty) return 'Enter a password';
                          if (_signUp && s.length < 8) return 'Use at least 8 characters';
                          return null;
                        },
                      ),
                      if (!_signUp)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: _forgot, child: const Text('Forgot password?', style: TextStyle(color: C.inkSoft, fontWeight: FontWeight.w700))),
                        )
                      else
                        const SizedBox(height: 12),
                      ClayButton(label: _signUp ? 'Create account' : 'Sign in', loading: _busy, onPressed: _submit),
                      const SizedBox(height: 16),
                      Row(children: const [
                        Expanded(child: Divider(color: C.sunken, thickness: 1.5)),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: C.inkSoft, fontWeight: FontWeight.w700))),
                        Expanded(child: Divider(color: C.sunken, thickness: 1.5)),
                      ]),
                      const SizedBox(height: 16),
                      _GoogleButton(loading: _googleBusy, onTap: _google),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => setState(() => _signUp = !_signUp),
                    child: Text.rich(TextSpan(
                      style: const TextStyle(color: C.inkSoft, fontWeight: FontWeight.w600, fontSize: 14.5),
                      children: [
                        TextSpan(text: _signUp ? 'Already in the hive? ' : 'New here? '),
                        TextSpan(text: _signUp ? 'Sign in' : 'Create an account', style: const TextStyle(color: C.honeyDeep, fontWeight: FontWeight.w800)),
                      ],
                    )),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Press(
        onTap: loading ? null : onTap,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: clayDeco(color: C.surface, radius: 27, depth: .7),
          child: loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/icons/google.png', width: 22, height: 22),
                  const SizedBox(width: 12),
                  const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
        ),
      );
}
