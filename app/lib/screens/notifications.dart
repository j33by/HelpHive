import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/reactions.dart';
import 'post_detail.dart';
import 'profile.dart';
import '../layout.dart';

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key});
  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  final _scroll = ScrollController();
  final List<Notif> _items = [];
  bool _loading = true;
  bool _more = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppState.I.tab.addListener(_onTab);
    AppState.I.addListener(_onBadge);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    AppState.I.tab.removeListener(_onTab);
    AppState.I.removeListener(_onBadge);
    _scroll.dispose();
    super.dispose();
  }

  void _onTab() {
    if (AppState.I.tab.value == 2) _load(quiet: true);
  }

  // new alerts arrived while this tab is open
  void _onBadge() {
    if (AppState.I.tab.value == 2 && AppState.I.notifBadge > 0) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
      });
    }
    try {
      final r = await Api.notifications();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.items);
        _more = r.hasMore;
        _loading = false;
        _error = null;
      });
      // opening the tab counts as seeing them; the dots stay for this visit
      if (AppState.I.tab.value == 2 && r.items.any((n) => !n.read)) {
        Api.readAllNotifications().then((_) => AppState.I.setBadges(notifications: 0)).catchError((_) {});
      }
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _error = friendly(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more || _items.isEmpty) return;
    _loadingMore = true;
    try {
      final r = await Api.notifications(before: _items.last.createdAt);
      if (!mounted) return;
      setState(() {
        final seen = _items.map((n) => n.id).toSet();
        _items.addAll(r.items.where((n) => !seen.contains(n.id)));
        _more = r.hasMore;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  (String, String?) _text(Notif n) {
    final q = n.snippet == null ? null : '“${n.snippet}”';
    switch (n.type) {
      case 'friend_request':
        return ('sent you a friend request', null);
      case 'friend_accepted':
        return ('accepted your friend request', null);
      case 'post_reaction':
        return ('reacted to your post', null);
      case 'post_comment':
        return ('commented on your post', q);
      case 'comment_reply':
        return ('replied to your comment', q);
      case 'comment_reaction':
        return ('reacted to your comment', null);
      default:
        return ('did something', null);
    }
  }

  void _open(Notif n) {
    if (!n.read) {
      n.read = true;
      Api.readNotification(n.id).catchError((_) {});
      setState(() {});
    }
    if (n.type.startsWith('friend') && n.actor.id.isNotEmpty) {
      Navigator.push(context, appRoute(ProfileScreen(userId: n.actor.id)));
    } else if (n.postId != null) {
      Navigator.push(context, appRoute(PostDetailScreen(postId: n.postId)));
    }
  }

  Future<void> _delete(Notif n) async {
    final i = _items.indexWhere((x) => x.id == n.id);
    if (i < 0) return;
    setState(() => _items.removeAt(i));
    try {
      await Api.deleteNotification(n.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items.insert(i.clamp(0, _items.length), n));
      toast(context, friendly(e));
    }
  }

  Future<void> _clearAll() async {
    final ok = await confirm(
      context,
      title: 'Clear all alerts?',
      body: 'Every notification will be removed for good.',
      yes: 'Clear all',
      danger: true,
    );
    if (!ok || !mounted) return;
    final backup = List<Notif>.of(_items);
    setState(() {
      _items.clear();
      _more = false;
    });
    AppState.I.setBadges(notifications: 0);
    try {
      await Api.deleteAllNotifications();
    } catch (e) {
      if (!mounted) return;
      setState(() => _items.addAll(backup));
      toast(context, friendly(e));
    }
  }

  Future<void> _menu(Notif n) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: C.sunken, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            if (!n.read) ...[
              ClayButton(label: 'Mark as read', icon: 'check', tone: ClayTone.soft, onPressed: () => Navigator.pop(ctx, 'read')),
              const SizedBox(height: 12),
            ],
            ClayButton(label: 'Delete notification', icon: 'trash', tone: ClayTone.danger, onPressed: () => Navigator.pop(ctx, 'delete')),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'delete') {
      await _delete(n);
    } else if (choice == 'read' && !n.read) {
      setState(() => n.read = true);
      Api.readNotification(n.id).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(children: [
            const Expanded(
              child: Text('Alerts', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.4)),
            ),
            if (_items.isNotEmpty)
              ClayButton(label: 'Clear all', icon: 'trash', tone: ClayTone.soft, small: true, expanded: false, onPressed: _clearAll),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _items.isEmpty
                  ? Failed(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      color: C.honeyDeep,
                      backgroundColor: C.surface,
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(children: const [SizedBox(height: 80), Empty(icon: 'bell', title: 'All quiet', subtitle: 'Friend requests, reactions and comments will show up here.')])
                          : ListView.separated(
                              controller: _scroll,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final n = _items[i];
                                final (what, quote) = _text(n);
                                return Dismissible(
                                  key: ValueKey(n.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 24),
                                    decoration: BoxDecoration(color: C.rose.withValues(alpha: .15), borderRadius: BorderRadius.circular(22)),
                                    child: const HIcon('trash', color: C.rose),
                                  ),
                                  onDismissed: (_) => _delete(n),
                                  child: ClayCard(
                                    radius: 22,
                                    depth: .5,
                                    padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                                    color: n.read ? C.surface : C.honeyPale,
                                    onTap: () => _open(n),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Avatar(url: n.actor.avatarUrl, name: n.actor.display, size: 46),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text.rich(TextSpan(children: [
                                            TextSpan(text: n.actor.display, style: const TextStyle(fontWeight: FontWeight.w800)),
                                            TextSpan(text: ' $what'),
                                          ]), style: const TextStyle(height: 1.3, fontSize: 14.5)),
                                          if (quote != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(quote, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.inkSoft, fontSize: 13.5)),
                                            ),
                                          const SizedBox(height: 4),
                                          Row(children: [
                                            Text(ago(n.createdAt), style: const TextStyle(color: C.inkSoft, fontSize: 12)),
                                            if ((n.type == 'post_reaction' || n.type == 'comment_reaction') && reactionKinds.contains(n.snippet)) ...[
                                              const SizedBox(width: 8),
                                              ReactionImg(n.snippet!, size: 16),
                                            ],
                                          ]),
                                        ]),
                                      ),
                                      Column(children: [
                                        Press(
                                          onTap: () => _menu(n),
                                          scale: .9,
                                          child: Container(
                                            width: 40,
                                            height: 32,
                                            alignment: Alignment.center,
                                            child: const HIcon('more', size: 20, color: C.inkSoft),
                                          ),
                                        ),
                                        if (!n.read)
                                          Container(
                                            margin: const EdgeInsets.only(top: 4, right: 4),
                                            width: 9,
                                            height: 9,
                                            decoration: const BoxDecoration(color: C.honeyDeep, shape: BoxShape.circle),
                                          ),
                                      ]),
                                    ]),
                                  ),
                                );
                              },
                            ),
                    ),
        ),
      ]),
    );
  }
}
