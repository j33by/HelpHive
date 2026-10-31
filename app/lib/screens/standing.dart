import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _when(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// The only screen a banned account sees: that it is banned, why, and how to appeal.
class BannedScreen extends StatefulWidget {
  const BannedScreen({super.key});
  @override
  State<BannedScreen> createState() => _BannedScreenState();
}

class _BannedScreenState extends State<BannedScreen> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await AppState.I.refreshStanding();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I.standing;
        final appeal = s.appeal;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ClayCard(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: C.rose.withValues(alpha: .14), shape: BoxShape.circle),
                        child: const Icon(Icons.block, color: C.rose, size: 30),
                      ),
                      const SizedBox(height: 18),
                      const Text('Your account is banned', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.3)),
                      const SizedBox(height: 8),
                      const Text('You cannot use HelpHive while the ban is in place. Your posts and profile are hidden from other people.', style: TextStyle(color: C.inkSoft, height: 1.4)),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: sunkenDeco(radius: 16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('REASON', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: C.inkSoft)),
                          const SizedBox(height: 6),
                          Text((s.reason ?? '').isEmpty ? 'No reason was recorded.' : s.reason!, style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      if (appeal != null) ...[
                        const SizedBox(height: 14),
                        _AppealStatus(appeal: appeal),
                      ],
                      const SizedBox(height: 22),
                      if (s.canAppeal) ...[
                        ClayButton(label: appeal == null ? 'Appeal this decision' : 'Send another appeal', onPressed: () => _appeal(context)),
                        const SizedBox(height: 10),
                      ],
                      ClayButton(label: 'Check again', tone: ClayTone.soft, loading: _checking, onPressed: _checking ? null : _check),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: () => Supabase.instance.client.auth.signOut(),
                          child: const Text('Sign out', style: TextStyle(color: C.inkSoft, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _appeal(BuildContext context) async {
    final sent = await showAppealDialog(context);
    if (sent == true) await AppState.I.refreshStanding();
  }
}

class _AppealStatus extends StatelessWidget {
  const _AppealStatus({required this.appeal});
  final StandingAppeal appeal;
  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (appeal.status) {
      'pending' => ('Appeal sent', 'The team will look at it. You will see the answer here.'),
      'denied' => ('Appeal declined', appeal.decisionReason ?? ''),
      _ => ('Appeal accepted', appeal.decisionReason ?? ''),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: C.shadowDark), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (body.isNotEmpty) ...[const SizedBox(height: 4), Text(body, style: const TextStyle(color: C.inkSoft, height: 1.35))],
      ]),
    );
  }
}

Future<bool?> showAppealDialog(BuildContext context) {
  final ctl = TextEditingController();
  String? error;
  var busy = false;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Appeal this decision', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tell the team why this should be reviewed. Be specific and polite.', style: TextStyle(color: C.inkSoft)),
          const SizedBox(height: 12),
          TextField(controller: ctl, maxLines: 5, maxLength: 1000, decoration: InputDecoration(hintText: 'Write your message…', errorText: error)),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: C.inkSoft))),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    setS(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await Api.appeal(ctl.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setS(() {
                        busy = false;
                        error = friendly(e);
                      });
                    }
                  },
            child: const Text('Send appeal', style: TextStyle(color: C.honeyDeep, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ),
  );
}

/// Slim bar under the top of the app while the account is restricted.
class StandingBanner extends StatelessWidget {
  const StandingBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I.standing;
        if (!s.restricted) return const SizedBox.shrink();
        return Material(
          color: C.rose.withValues(alpha: .14),
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: () => showStandingSheet(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.schedule, size: 18, color: C.rose),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your account is restricted until ${_when(s.until!)}. You can read, but not post, comment, react or message.',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.rose)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Reason, strikes and recent actions on the account.
Future<void> showStandingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => ListenableBuilder(
      listenable: AppState.I,
      builder: (ctx, _) {
        final s = AppState.I.standing;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .7,
          maxChildSize: .92,
          builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(22, 18, 22, 28), children: [
            const Text('Account standing', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (s.restricted) ...[
              Text('Restricted until ${_when(s.until!)}', style: const TextStyle(fontWeight: FontWeight.w800, color: C.rose)),
              const SizedBox(height: 4),
              Text(s.reason ?? '', style: const TextStyle(height: 1.4)),
              const SizedBox(height: 4),
              const Text('The restriction ends by itself. Repeat restrictions last longer each time.', style: TextStyle(color: C.inkSoft, fontSize: 13)),
            ] else
              const Text('Your account is in good standing.', style: TextStyle(fontWeight: FontWeight.w700)),
            if (s.strikes > 0) ...[
              const SizedBox(height: 14),
              Text('Strikes: ${s.strikes}${s.strikeLimit != null ? ' (a restriction applies automatically at ${s.strikeLimit})' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
            if (s.canAppeal) ...[
              const SizedBox(height: 14),
              ClayButton(label: 'Appeal', tone: ClayTone.soft, onPressed: () async {
                final sent = await showAppealDialog(ctx);
                if (sent == true) await AppState.I.refreshStanding();
              }),
            ],
            if (s.appeal != null) ...[const SizedBox(height: 12), _AppealStatus(appeal: s.appeal!)],
            const SizedBox(height: 20),
            const Text('RECENT ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: C.inkSoft)),
            const SizedBox(height: 8),
            if (s.history.isEmpty)
              const Text('Nothing yet.', style: TextStyle(color: C.inkSoft))
            else
              for (final e in s.history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e.label} · ${_when(e.createdAt)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    if (e.reason.isNotEmpty) Text(e.reason, style: const TextStyle(color: C.inkSoft, height: 1.35)),
                  ]),
                ),
          ]),
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// reporting
// ---------------------------------------------------------------------------
const _reportReasons = <(String, String)>[
  ('spam', 'Spam or advertising'),
  ('harassment', 'Harassment or abuse'),
  ('inappropriate', 'Inappropriate content'),
  ('scam', 'Scam or fraud'),
  ('misinformation', 'Misleading information'),
  ('other', 'Something else'),
];

Future<void> showReportSheet(BuildContext context, {required String type, required String id}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) {
      String? reason;
      String? error;
      var busy = false;
      final details = TextEditingController();
      return StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Report', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Tell the HelpHive team what is wrong. The person is not told who reported.', style: TextStyle(color: C.inkSoft)),
            const SizedBox(height: 10),
            for (final r in _reportReasons)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                leading: Icon(reason == r.$1 ? Icons.radio_button_checked : Icons.radio_button_off, color: reason == r.$1 ? C.honeyDeep : C.inkSoft),
                onTap: () => setS(() => reason = r.$1),
              ),
            TextField(controller: details, maxLines: 2, maxLength: 500, decoration: const InputDecoration(hintText: 'Anything else we should know? (optional)')),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(color: C.rose))),
            ClayButton(
              label: 'Send report',
              loading: busy,
              onPressed: reason == null || busy
                  ? null
                  : () async {
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await Api.report(type: type, id: id, reason: reason!, details: details.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setS(() {
                          busy = false;
                          error = friendly(e);
                        });
                      }
                    },
            ),
          ]),
        ),
      );
    },
  );
  if (done == true && context.mounted) toast(context, 'Thanks. The team will take a look.');
}
