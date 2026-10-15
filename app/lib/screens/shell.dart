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
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: C.surface,
                border: const Border(top: BorderSide(color: C.sunken, width: 1)),
                boxShadow: [
                  BoxShadow(color: C.shadowDark.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, -3)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 64,
                  child: Row(children: [
                    for (var n = 0; n < _tabs.length; n++)
                      Expanded(
                        child: _NavItem(
                          icon: i == n ? _tabs[n].$2 : _tabs[n].$1,
                          label: _tabs[n].$3,
                          selected: i == n,
                          badge: n == 2 ? _app.notifBadge : (n == 3 ? _app.msgBadge : 0),
                          onTap: () => _app.tab.value = n,
                        ),
                      ),
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
        scale: .92,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(clipBehavior: Clip.none, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 58,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? C.honeyPale : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: HIcon(icon, size: 23, color: selected ? C.ink : C.inkSoft),
            ),
            if (badge > 0) Positioned(right: 4, top: -3, child: CountDot(badge)),
          ]),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.1,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? C.ink : C.inkSoft,
            ),
          ),
        ]),
      );
}
