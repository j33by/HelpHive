import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import 'feed.dart';
import 'messages.dart';
import 'notifications.dart';
import 'people.dart';
import 'profile.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _app = AppState.I;
  DateTime? _lastBack;

  static const _tabs = [
    ('home', 'home_fill', 'Feed'),
    ('people', 'people_fill', 'People'),
    ('bell', 'bell_fill', 'Alerts'),
    ('chat', 'chat_fill', 'Chats'),
    ('user', 'user_fill', 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_app, _app.tab]),
      builder: (context, _) {
        final i = _app.tab.value;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (i != 0) {
              _app.tab.value = 0;
              return;
            }
            final now = DateTime.now();
            if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
              Navigator.of(context).maybePop();
              return;
            }
            _lastBack = now;
            toast(context, 'Press back again to leave');
          },
          child: Scaffold(
            body: IndexedStack(index: i, children: const [
              FeedTab(),
              PeopleTab(),
              NotificationsTab(),
              MessagesTab(),
              ProfileScreen(),
            ]),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Container(
                  height: 68,
                  decoration: clayDeco(radius: 34, depth: .8),
                  child: Row(children: [
                    for (var n = 0; n < _tabs.length; n++)
                      Expanded(child: _NavItem(
                        icon: i == n ? _tabs[n].$2 : _tabs[n].$1,
                        label: _tabs[n].$3,
                        selected: i == n,
                        badge: n == 2 ? _app.notifBadge : (n == 3 ? _app.msgBadge : 0),
                        onTap: () => _app.tab.value = n,
                      )),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.badge, required this.onTap});
  final String icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        child: Center(
          child: Stack(clipBehavior: Clip.none, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 10, vertical: 9),
              decoration: BoxDecoration(color: selected ? C.honey : Colors.transparent, borderRadius: BorderRadius.circular(24)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                HIcon(icon, size: 24, color: selected ? C.ink : C.inkSoft),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                ],
              ]),
            ),
            if (badge > 0) Positioned(right: -2, top: -4, child: CountDot(badge)),
          ]),
        ),
      );
}
