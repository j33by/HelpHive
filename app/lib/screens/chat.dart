import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../models.dart';
import '../platform.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/reactions.dart';
import 'profile.dart';
import '../layout.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId, required this.other, this.embedded = false});
  final String conversationId;
  final UserLite other;

  /// Shown inside the chats tab next to the list (desktop), so no back button.
  final bool embedded;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Message> _msgs = []; // oldest first
  DateTime? _otherReadAt;
  bool _loading = true;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _sending = false;
  String? _error;
  Message? _replyTo;
  Timer? _poll;
  int _tmp = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(() => setState(() {}));
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadOlder();
    });
    _initial();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    AppState.I.refreshBadges();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _initial() async {
    try {
      final r = await Api.messages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _msgs = r.messages;
        _hasMore = r.hasMore;
        _otherReadAt = r.otherReadAt;
        _loading = false;
        _error = null;
      });
      _markRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendly(e);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_loading || _error != null) return;
    try {
      final r = await Api.messages(widget.conversationId);
      if (!mounted) return;
      final earliest = r.messages.isEmpty ? null : r.messages.first.createdAt;
      final older = earliest == null ? <Message>[] : _msgs.where((m) => !m.pending && m.createdAt.isBefore(earliest)).toList();
      final hadIncoming = r.messages.any((m) => m.senderId != myId && !_msgs.any((x) => x.id == m.id));
      setState(() {
        _msgs = [...older, ...r.messages, ..._msgs.where((m) => m.pending)];
        _otherReadAt = r.otherReadAt;
      });
      if (hadIncoming) _markRead();
    } catch (_) {
      // transient; the next tick tries again
    }
  }

  void _markRead() {
    Api.markRead(widget.conversationId).then((_) => AppState.I.refreshBadges()).catchError((_) {});
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore) return;
    final first = _msgs.where((m) => !m.pending).firstOrNull;
    if (first == null) return;
    _loadingOlder = true;
    try {
      final r = await Api.messages(widget.conversationId, before: first.createdAt);
      if (!mounted) return;
      setState(() {
        final seen = _msgs.map((m) => m.id).toSet();
        _msgs = [...r.messages.where((m) => !seen.contains(m.id)), ..._msgs];
        _hasMore = r.hasMore;
      });
    } catch (_) {
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final reply = _replyTo;
    final temp = Message(
      id: 'tmp-${_tmp++}',
      senderId: myId,
      body: text,
      deleted: false,
      createdAt: DateTime.now(),
      replyTo: reply == null ? null : ReplyRef(id: reply.id, body: reply.body, senderId: reply.senderId, deleted: false),
      reactions: {},
      pending: true,
    );
    setState(() {
      _msgs.add(temp);
      _input.clear();
      _replyTo = null;
      _sending = true;
    });
    try {
      await Api.sendMessage(widget.conversationId, text, replyTo: reply?.id);
      await _refresh();
      if (mounted) setState(() => _msgs.removeWhere((m) => m.id == temp.id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.removeWhere((m) => m.id == temp.id);
        _input.text = text;
        _replyTo = reply;
      });
      toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(Message m, String? kind) async {
    final prev = m.myReaction;
    final prevMap = Map<String, int>.from(m.reactions);
    setState(() {
      if (prev != null) {
        final n = (m.reactions[prev] ?? 1) - 1;
        if (n <= 0) {
          m.reactions.remove(prev);
        } else {
          m.reactions[prev] = n;
        }
      }
      if (kind != null) m.reactions[kind] = (m.reactions[kind] ?? 0) + 1;
      m.myReaction = kind;
    });
    try {
      await Api.reactMessage(m.id, kind);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        m.reactions = prevMap;
        m.myReaction = prev;
      });
      toast(context, friendly(e));
    }
  }

  Future<void> _actions(Message m) async {
    if (m.pending || m.deleted) return;
    final mine = m.senderId == myId;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: clayDeco(radius: 34, depth: .55),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (final k in reactionKinds)
                  Press(
                    scale: 1.12,
                    onTap: () => Navigator.pop(ctx, m.myReaction == k ? 'r:' : 'r:$k'),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: m.myReaction == k ? const BoxDecoration(color: C.honeyPale, shape: BoxShape.circle) : null,
                      child: ReactionImg(k, size: 34),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            _SheetRow(icon: 'reply', label: 'Reply', onTap: () => Navigator.pop(ctx, 'reply')),
            _SheetRow(icon: 'comment', label: 'Copy text', onTap: () => Navigator.pop(ctx, 'copy')),
            if (mine) _SheetRow(icon: 'trash', label: 'Unsend', danger: true, onTap: () => Navigator.pop(ctx, 'unsend')),
          ]),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.startsWith('r:')) {
      final k = choice.substring(2);
      _react(m, k.isEmpty ? null : k);
    } else if (choice == 'reply') {
      setState(() => _replyTo = m);
    } else if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body));
      if (mounted) toast(context, 'Copied');
    } else if (choice == 'unsend') {
      final ok = await confirm(context, title: 'Unsend this message?', body: 'It disappears for both of you.', yes: 'Unsend', danger: true);
      if (!ok) return;
      try {
        await Api.unsend(m.id);
        if (mounted) {
          setState(() {
            m.deleted = true;
            m.body = '';
            m.reactions = {};
          });
        }
      } catch (e) {
        if (mounted) toast(context, friendly(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.other;
    final shown = _msgs.reversed.toList(); // newest first for the reversed list
    final lastMineIdx = shown.indexWhere((m) => m.senderId == myId && !m.pending);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        automaticallyImplyLeading: false,
        leading: widget.embedded
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(child: ClayIconButton(icon: 'back', size: 40, onTap: () => Navigator.pop(context))),
              ),
        titleSpacing: widget.embedded ? 20 : 12,
        title: Press(
          onTap: o.id.isEmpty ? null : () => Navigator.push(context, appRoute(ProfileScreen(userId: o.id))),
          child: Row(children: [
            Avatar(url: o.avatarUrl, name: o.display, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text('@${o.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: C.inkSoft, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Failed(message: _error!, onRetry: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _initial();
                    })
                  : shown.isEmpty
                      ? Empty(icon: 'chat', title: 'Say hello to ${o.display}', subtitle: 'Your messages show up here.')
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: shown.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= shown.length) {
                              return const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))));
                            }
                            final m = shown[i];
                            final mine = m.senderId == myId;
                            final older = i + 1 < shown.length ? shown[i + 1] : null;
                            final showTime = older == null || m.createdAt.difference(older.createdAt).inMinutes >= 30;
                            final seen = i == lastMineIdx && _otherReadAt != null && !_otherReadAt!.isBefore(m.createdAt);
                            return Column(children: [
                              if (showTime)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(_stamp(m.createdAt), style: const TextStyle(color: C.inkSoft, fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                              _Bubble(
                                m: m,
                                mine: mine,
                                tight: older != null && older.senderId == m.senderId && !showTime,
                                otherName: o.display,
                                onActions: () => _actions(m),
                              ),
                              if (mine && (m.pending || seen || i == lastMineIdx))
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 3, right: 6),
                                    child: Text(m.pending ? 'Sending…' : (seen ? 'Seen' : 'Sent'), style: const TextStyle(color: C.inkSoft, fontSize: 11.5, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                            ]);
                          },
                        ),
        ),
        _composer(o),
      ]),
    );
  }

  String _stamp(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    final sameDay = DateTime.now().difference(t).inHours < 24 && DateTime.now().day == t.day;
    return sameDay ? '$h:$mm $ap' : '${ago(t)} · $h:$mm $ap';
  }

  Widget _composer(UserLite o) {
    final can = _input.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(color: C.bg, boxShadow: [BoxShadow(color: C.shadowDark.withValues(alpha: .5), blurRadius: 14, offset: const Offset(0, -4))]),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_replyTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: BoxDecoration(color: C.honeyPale, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_replyTo!.senderId == myId ? 'Replying to yourself' : 'Replying to ${o.display}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.honeyDeep)),
                      Text(_replyTo!.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
                  Press(onTap: () => setState(() => _replyTo = null), child: const Padding(padding: EdgeInsets.all(8), child: HIcon('close', size: 16, color: C.inkSoft))),
                ]),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  // desktop: Enter sends, Shift+Enter starts a new line
                  onKeyEvent: (node, e) {
                    if (isDesktop && e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                      if (can) _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ClayField(controller: _input, hint: 'Message', maxLines: 5, minLines: 1, maxLength: 2000),
                ),
              ),
              const SizedBox(width: 10),
              ClayIconButton(icon: can ? 'send_fill' : 'send', size: 50, bg: can ? C.honey : C.surface, onTap: can ? _send : null),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.icon, required this.label, required this.onTap, this.danger = false});
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Row(children: [
            HIcon(icon, size: 22, color: danger ? C.rose : C.ink),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: danger ? C.rose : C.ink)),
          ]),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m, required this.mine, required this.tight, required this.otherName, required this.onActions});
  final Message m;
  final bool mine;
  final bool tight;
  final String otherName;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * .76;
    final r = m.replyTo;
    final reactions = m.reactions.entries.where((e) => e.value > 0).toList();
    final bg = m.deleted ? C.sunken : (mine ? C.honey : C.surface);

    return Padding(
      padding: EdgeInsets.only(top: tight ? 3 : 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Press(
              onLongPress: onActions,
              onTap: null,
              scale: .985,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: m.deleted
                    ? BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20))
                    : clayDeco(color: bg, radius: 20, depth: .4).copyWith(
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(mine ? 20 : 6),
                          bottomRight: Radius.circular(mine ? 6 : 20),
                        ),
                      ),
                child: Opacity(
                  opacity: m.pending ? .6 : 1,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (r != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                        decoration: BoxDecoration(
                          color: (mine ? Colors.white : C.sunken).withValues(alpha: mine ? .45 : 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.senderId == myId ? 'You' : otherName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                          Text(r.deleted ? 'Message unsent' : r.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, fontStyle: r.deleted ? FontStyle.italic : FontStyle.normal)),
                        ]),
                      ),
                    Text(
                      m.deleted ? 'Message unsent' : m.body,
                      style: TextStyle(fontSize: 15.5, height: 1.35, fontStyle: m.deleted ? FontStyle.italic : FontStyle.normal, color: m.deleted ? C.inkSoft : C.ink),
                    ),
                  ]),
                ),
              ),
            ),
            if (reactions.isNotEmpty)
              Transform.translate(
                offset: const Offset(0, -6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: clayDeco(radius: 14, depth: .3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final e in reactions) ...[
                      ReactionImg(e.key, size: 15),
                      if (e.value > 1) Padding(padding: const EdgeInsets.only(left: 2, right: 4), child: Text('${e.value}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))) else const SizedBox(width: 3),
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
