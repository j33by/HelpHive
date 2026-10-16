import 'package:flutter/material.dart';
import '../app_state.dart';
import '../layout.dart';
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
  final _stackKey = GlobalKey();
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
        final wide = isWide(context);
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
            body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (wide)
                _Sidebar(
                  tabs: _tabs,
                  index: i,
                  expanded: MediaQuery.sizeOf(context).width >= Bp.full,
                  badges: [0, 0, _app.notifBadge, _app.msgBadge, 0],
                  onSelect: (n) => _app.tab.value = n,
                ),
              Expanded(
                child: IndexedStack(key: _stackKey, index: i, children: const [
                  ContentColumn(maxWidth: 720, child: FeedTab()),
                  ContentColumn(maxWidth: 1040, child: PeopleTab()),
                  ContentColumn(maxWidth: 720, child: NotificationsTab()),
                  ContentColumn(maxWidth: 1240, child: MessagesTab()),
                  ProfileScreen(),
                ]),
              ),
            ]),
            bottomNavigationBar: wide
                ? null
                : SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: Container(
                        height: 70,
                        decoration: clayDeco(radius: 35, depth: .8),
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
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 46,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? C.honey : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: HIcon(icon, size: 22, color: selected ? C.ink : C.inkSoft),
              ),
              if (badge > 0) Positioned(right: -2, top: -5, child: CountDot(badge)),
            ]),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.1,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                color: selected ? C.ink : C.inkSoft,
              ),
            ),
          ]),
        ),
      );
}

/// Desktop navigation: a full side bar with labels, or a slim icon rail on
/// narrower windows. The phone layout keeps the floating bar instead.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.tabs, required this.index, required this.expanded, required this.badges, required this.onSelect});
  final List<(String, String, String)> tabs;
  final int index;
  final bool expanded;
  final List<int> badges;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final me = AppState.I.me;
    return Container(
      width: expanded ? 248 : 92,
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(right: BorderSide(color: C.sunken)),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(expanded ? 16 : 8, 22, expanded ? 16 : 8, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
              if (expanded) const SizedBox(width: 8),
              Image.asset('assets/icons/bee.png', width: 36, height: 36),
              if (expanded) ...[
                const SizedBox(width: 10),
                const Text('HelpHive', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.4)),
              ],
            ]),
            const SizedBox(height: 28),
            Expanded(
              child: SingleChildScrollView(
                child: Column(children: [
                  for (var n = 0; n < tabs.length; n++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: expanded
                          ? _SideItem(
                              icon: index == n ? tabs[n].$2 : tabs[n].$1,
                              label: tabs[n].$3,
                              selected: index == n,
                              badge: badges[n],
                              onTap: () => onSelect(n),
                            )
                          : SizedBox(
                              height: 64,
                              child: _NavItem(
                                icon: index == n ? tabs[n].$2 : tabs[n].$1,
                                label: tabs[n].$3,
                                selected: index == n,
                                badge: badges[n],
                                onTap: () => onSelect(n),
                              ),
                            ),
                    ),
                ]),
              ),
            ),
            if (me != null)
              Press(
                onTap: () => onSelect(4),
                scale: .97,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
                    Avatar(url: me.avatarUrl, name: me.display, size: 38),
                    if (expanded) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(me.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                          Text('@${me.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.inkSoft, fontSize: 12)),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({required this.icon, required this.label, required this.selected, required this.badge, required this.onTap});
  final String icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Press(
        onTap: widget.onTap,
        scale: .98,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: sel ? C.honey : (_hover ? C.honeyPale : Colors.transparent),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(children: [
            HIcon(widget.icon, size: 22, color: sel ? C.ink : C.inkSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                style: TextStyle(fontSize: 15.5, fontWeight: sel ? FontWeight.w800 : FontWeight.w700, color: sel ? C.ink : C.inkSoft),
              ),
            ),
            if (widget.badge > 0) CountDot(widget.badge),
          ]),
        ),
      ),
    );
  }
}
