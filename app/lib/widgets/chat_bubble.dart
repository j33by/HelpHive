import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../layout.dart';
import '../models.dart';
import '../screens/post_detail.dart';
import '../screens/profile.dart';
import '../services/alerts.dart';
import '../services/data.dart';
import '../theme.dart';
import 'clay.dart';
import 'reactions.dart';

const double _size = 60;

/// A draggable chat head floating over the app. Tap it to open a quick panel
/// with recent messages (like / reply right there) and alert previews.
/// Sits in a Stack; empty areas let touches through to the app below.
class ChatBubbleLayer extends StatefulWidget {
  const ChatBubbleLayer({super.key});
  @override
  State<ChatBubbleLayer> createState() => _ChatBubbleLayerState();
}

class _ChatBubbleLayerState extends State<ChatBubbleLayer> with SingleTickerProviderStateMixin {
  // remembered while the app runs
  static Offset? _pos;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  bool _open = false;
  bool _dragging = false;
  int _seg = 0; // 0 messages, 1 alerts

  @override
  void initState() {
    super.initState();
    Alerts.I.latest.addListener(_onIncoming);
    Alerts.I.closePanel.addListener(_onClose);
  }

  @override
  void dispose() {
    Alerts.I.latest.removeListener(_onIncoming);
    Alerts.I.closePanel.removeListener(_onClose);
    _pulse.dispose();
    super.dispose();
  }

  void _onClose() {
    if (_open && mounted) setState(() => _open = false);
  }

  void _onIncoming() {
    if (Alerts.I.latest.value != null && !_open) _pulse.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, AppState.I.tab, Alerts.I, Alerts.I.latest]),
      builder: (context, _) {
        // the Chats tab already is the chat list
        if (AppState.I.tab.value == 3) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        final w = mq.size.width, h = mq.size.height;
        final minY = mq.padding.top + 8;
        final maxY = h - mq.padding.bottom - 100 - _size; // stays above the nav bar
        final p = _pos ?? Offset(w - _size - 8, h * .55);
        final pos = Offset(p.dx.clamp(8, w - _size - 8), p.dy.clamp(minY, maxY < minY ? minY : maxY));
        final onRight = pos.dx + _size / 2 > w / 2;
        final incoming = Alerts.I.latest.value;
        final unread = AppState.I.msgBadge + AppState.I.notifBadge;
        final head = _headUser();

        return Stack(children: [
          if (_open) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = false),
                child: ColoredBox(color: Colors.black.withValues(alpha: .28)),
              ),
            ),
            _panel(context, mq),
          ],
          if (!_open && incoming != null)
            Positioned(
              top: pos.dy + 4,
              left: onRight ? null : pos.dx + _size + 8,
              right: onRight ? w - pos.dx + 8 : null,
              child: Material(
                type: MaterialType.transparency,
                child: GestureDetector(
                  onTap: () {
                    Alerts.I.dismissLatest();
                    setState(() {
                      _seg = incoming.isMessage ? 0 : 1;
                      _open = true;
                    });
                  },
                  child: _Preview(incoming),
                ),
              ),
            ),
          Positioned(
            left: pos.dx,
            top: pos.dy,
            child: Material(
              type: MaterialType.transparency,
              child: GestureDetector(
                onTap: () {
                  Alerts.I.dismissLatest();
                  setState(() {
                    _seg = (AppState.I.msgBadge == 0 && AppState.I.notifBadge > 0) ? 1 : 0;
                    _open = !_open;
                  });
                  if (_open) Alerts.I.check();
                },
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (d) => setState(() => _pos = Offset(
                      (pos.dx + d.delta.dx).clamp(0, w - _size),
                      (pos.dy + d.delta.dy).clamp(minY, maxY < minY ? minY : maxY),
                    )),
                onPanEnd: (_) => setState(() {
                  _dragging = false;
                  final q = _pos ?? pos;
                  _pos = Offset(q.dx + _size / 2 > w / 2 ? w - _size - 8 : 8, q.dy); // snap to the nearest edge
                }),
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final bump = _pulse.isAnimating ? .3 * math.sin(math.pi * _pulse.value) : 0.0;
                    return Transform.scale(scale: _dragging ? 1.1 : 1 + bump, child: child);
                  },
                  child: SizedBox(
                    width: _size,
                    height: _size,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Container(
                        width: _size,
                        height: _size,
                        decoration: clayDeco(color: C.honey, radius: _size, depth: .7),
                        alignment: Alignment.center,
                        child: head != null
                            ? Avatar(url: head.avatarUrl, name: head.display, size: 48)
                            : const HIcon('chat_fill', size: 28, color: C.ink),
                      ),
                      if (unread > 0) Positioned(right: -4, top: -4, child: CountDot(unread)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  /// The person whose unread message is newest, shown on the bubble itself.
  UserLite? _headUser() {
    for (final c in Alerts.I.conversations) {
      if (c.unread > 0) return c.user;
    }
    return null;
  }

  Widget _panel(BuildContext context, MediaQueryData mq) {
    final maxH = mq.size.height - mq.padding.top - mq.viewInsets.bottom - 40;
    return Positioned(
      top: mq.padding.top + 12,
      left: 12,
      right: 12,
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH < 220 ? 220 : maxH),
            child: Container(
              decoration: clayDeco(color: C.bg, radius: 28, depth: .8),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
                  child: Row(children: [
                    _SegButton(label: 'Messages', icon: 'chat_fill', count: AppState.I.msgBadge, selected: _seg == 0, onTap: () => setState(() => _seg = 0)),
                    const SizedBox(width: 8),
                    _SegButton(label: 'Alerts', icon: 'bell_fill', count: AppState.I.notifBadge, selected: _seg == 1, onTap: () => setState(() => _seg = 1)),
                    const Spacer(),
                    Press(
                      onTap: () => setState(() => _open = false),
                      scale: .9,
                      child: const SizedBox(width: 40, height: 40, child: Center(child: HIcon('close', size: 20, color: C.inkSoft))),
                    ),
                  ]),
                ),
                Flexible(child: _seg == 0 ? const _MessagesList() : const _AlertsList()),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({required this.label, required this.icon, required this.count, required this.selected, required this.onTap});
  final String label;
  final String icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        scale: .95,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: selected ? C.honey : C.sunken, borderRadius: BorderRadius.circular(19)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            HIcon(icon, size: 16, color: selected ? C.ink : C.inkSoft),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: selected ? C.ink : C.inkSoft)),
            if (count > 0) ...[const SizedBox(width: 6), CountDot(count)],
          ]),
        ),
      );
}

/// Small card that pops out beside the bubble when something arrives.
class _Preview extends StatelessWidget {
  const _Preview(this.i);
  final Incoming i;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 230),
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: clayDeco(color: C.surface, radius: 22, depth: .5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Avatar(url: i.user.avatarUrl, name: i.user.display, size: 34),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                HIcon(i.isMessage ? 'chat_fill' : 'bell_fill', size: 12, color: C.honeyDeep),
                const SizedBox(width: 4),
                Flexible(child: Text(i.user.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
              ]),
              Text(i.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.inkSoft, fontSize: 12.5, height: 1.25)),
            ]),
          ),
        ]),
      );
}

class _MessagesList extends StatelessWidget {
  const _MessagesList();
  @override
  Widget build(BuildContext context) {
    final convs = [...Alerts.I.conversations]..sort((a, b) {
        if ((a.unread > 0) != (b.unread > 0)) return a.unread > 0 ? -1 : 1;
        return b.lastAt.compareTo(a.lastAt);
      });
    final shown = convs.take(8).toList();
    if (shown.isEmpty) {
      return const Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 32), child: Empty(icon: 'chat', title: 'No messages yet', subtitle: 'New chats will pop up here.'));
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      itemCount: shown.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _MessageCard(key: ValueKey(shown[i].id), c: shown[i]),
    );
  }
}

class _MessageCard extends StatefulWidget {
  const _MessageCard({super.key, required this.c});
  final Conversation c;
  @override
  State<_MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<_MessageCard> {
  final _input = TextEditingController();
  bool _replying = false;
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Alerts.I.reply(widget.c, t);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _sending = false;
        _replying = false;
      });
      toast(context, 'Reply sent');
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, friendly(e));
    }
  }

  Future<void> _like() async {
    try {
      await Alerts.I.likeLast(widget.c);
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final canAct = !c.lastMine && !c.lastDeleted && c.lastId.isNotEmpty;
    final liked = Alerts.I.liked.contains(c.id);
    final text = c.lastDeleted ? 'Message unsent' : (c.lastMine ? 'You: ${c.lastBody}' : c.lastBody);
    return ClayCard(
      radius: 22,
      depth: .5,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      color: c.unread > 0 ? C.honeyPale : C.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Press(
          onTap: () {
            Alerts.I.openChat(c.id, c.user);
          },
          scale: .985,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(url: c.user.avatarUrl, name: c.user.display, size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(c.user.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
                  Text(ago(c.lastAt), style: const TextStyle(color: C.inkSoft, fontSize: 12)),
                ]),
                const SizedBox(height: 2),
                Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.3, color: c.unread > 0 ? C.ink : C.inkSoft, fontWeight: c.unread > 0 ? FontWeight.w700 : FontWeight.w500)),
              ]),
            ),
            if (c.unread > 0) ...[const SizedBox(width: 8), CountDot(c.unread)],
          ]),
        ),
        if (canAct) ...[
          const SizedBox(height: 8),
          Row(children: [
            _Action(icon: liked ? 'heart_fill' : 'heart', label: liked ? 'Liked' : 'Like', color: liked ? C.rose : C.inkSoft, onTap: liked ? null : _like),
            const SizedBox(width: 8),
            _Action(icon: 'reply', label: 'Reply', color: _replying ? C.honeyDeep : C.inkSoft, onTap: () => setState(() => _replying = !_replying)),
            const Spacer(),
            _Action(icon: 'chevron_right', label: 'Open', color: C.inkSoft, onTap: () => Alerts.I.openChat(c.id, c.user)),
          ]),
        ],
        if (_replying)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: sunkenDeco(radius: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    controller: _input,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(hintText: 'Reply to ${c.user.display}', border: InputBorder.none, counterText: '', isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 12)),
                    style: const TextStyle(fontSize: 14.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Press(
                onTap: _send,
                scale: .92,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: C.honey, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.ink))
                      : const HIcon('send_fill', size: 20, color: C.ink),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.color, required this.onTap});
  final String icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        scale: .93,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: C.sunken.withValues(alpha: .7), borderRadius: BorderRadius.circular(17)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            HIcon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: color)),
          ]),
        ),
      );
}

class _AlertsList extends StatelessWidget {
  const _AlertsList();
  @override
  Widget build(BuildContext context) {
    final items = Alerts.I.notifs.take(8).toList();
    if (items.isEmpty) {
      return const Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 32), child: Empty(icon: 'bell', title: 'All quiet', subtitle: 'Friend requests, reactions and comments will show up here.'));
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final n = items[i];
        final (what, quote) = notifSummary(n);
        return ClayCard(
          radius: 22,
          depth: .5,
          padding: const EdgeInsets.all(12),
          color: n.read ? C.surface : C.honeyPale,
          onTap: () {
            Alerts.I.markAlertRead(n);
            Alerts.I.closePanel.value++;
            final nav = navigatorKey.currentState;
            if (nav == null) return;
            if (n.type.startsWith('friend') && n.actor.id.isNotEmpty) {
              nav.push(appRoute(ProfileScreen(userId: n.actor.id)));
            } else if (n.postId != null) {
              nav.push(appRoute(PostDetailScreen(postId: n.postId)));
            }
          },
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              Avatar(url: n.actor.avatarUrl, name: n.actor.display, size: 44),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: C.honey, shape: BoxShape.circle, border: Border.all(color: C.surface, width: 1.5)),
                  alignment: Alignment.center,
                  child: (n.type.endsWith('reaction') && reactionKinds.contains(n.snippet))
                      ? ReactionImg(n.snippet!, size: 15)
                      : HIcon(notifIcon(n), size: 12, color: C.ink),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: n.actor.display, style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: ' $what'),
                  ]),
                  style: const TextStyle(height: 1.3, fontSize: 14),
                ),
                if (quote != null)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: C.sunken.withValues(alpha: .7), borderRadius: BorderRadius.circular(12)),
                    child: Text(quote, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.inkSoft, fontSize: 13, height: 1.3)),
                  ),
                const SizedBox(height: 4),
                Text(ago(n.createdAt), style: const TextStyle(color: C.inkSoft, fontSize: 12)),
              ]),
            ),
            if (!n.read)
              Container(margin: const EdgeInsets.only(top: 6, left: 6), width: 9, height: 9, decoration: const BoxDecoration(color: C.honeyDeep, shape: BoxShape.circle)),
          ]),
        );
      },
    );
  }
}
