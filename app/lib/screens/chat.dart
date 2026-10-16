import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/alerts.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/reactions.dart';

/// One conversation. `embedded` is the desktop split view (no back button).
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId, required this.other, this.embedded = false});
  final String conversationId;
  final UserLite other;
  final bool embedded;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Message> _msgs = []; // oldest first
  bool _loading = true;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;
  DateTime? _otherReadAt;
  Message? _replyTo;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    Alerts.I.activeConversation = widget.conversationId;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load(quiet: true));
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) _loadOlder();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (Alerts.I.activeConversation == widget.conversationId) Alerts.I.activeConversation = null;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final r = await Api.messages(widget.conversationId);
      if (!mounted) return;
      final pending = _msgs.where((m) => m.pending).toList();
      final changed = _msgs.isEmpty || r.messages.length != _msgs.where((m) => !m.pending).length || (r.messages.isNotEmpty && _msgs.isNotEmpty && r.messages.last.id != _msgs.where((m) => !m.pending).lastOrNull?.id);
      setState(() {
        // keep older pages that were already loaded
        final older = _msgs.where((m) => !m.pending && r.messages.isNotEmpty && m.createdAt.isBefore(r.messages.first.createdAt)).toList();
        _msgs = [...older, ...r.messages, ...pending];
        _hasMore = older.isNotEmpty ? _hasMore : r.hasMore;
        _otherReadAt = r.otherReadAt;
        _loading = false;
        _error = null;
      });
      if (changed || !quiet) _markRead();
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _error = friendly(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingMore || !_hasMore || _msgs.isEmpty) return;
    _loadingMore = true;
    try {
      final r = await Api.messages(widget.conversationId, before: _msgs.first.createdAt);
      if (!mounted) return;
      setState(() {
        _msgs = [...r.messages, ..._msgs];
        _hasMore = r.hasMore;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _markRead() async {
    try {
      await Api.markRead(widget.conversationId);
      AppState.I.refreshBadges(force: true);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final reply = _replyTo;
    final temp = Message(
      id: 'tmp_${DateTime.now().microsecondsSinceEpoch}',
      senderId: myId,
      body: text,
      deleted: false,
      createdAt: DateTime.now(),
      replyTo: reply == null ? null : ReplyRef(id: reply.id, body: reply.body, senderId: reply.senderId, deleted: reply.deleted),
      reactions: {},
      pending: true,
    );
    setState(() {
      _sending = true;
      _msgs = [..._msgs, temp];
      _replyTo = null;
      _input.clear();
    });
    try {
      await Api.sendMessage(widget.conversationId, text, replyTo: reply?.id);
      _msgs.removeWhere((m) => m.id == temp.id);
      await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.removeWhere((m) => m.id == temp.id);
        _input.text = text;
      });
      toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(Message m) async {
    if (m.pending || m.deleted) return;
    final pick = await pickReaction(context, current: m.myReaction);
    if (pick == null) return;
    final kind = pick.isEmpty ? null : pick;
    try {
      await Api.reactMessage(m.id, kind);
      _load(quiet: true);
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    }
  }

  Future<void> _unsend(Message m) async {
    final ok = await confirm(context, title: 'Unsend message?', body: 'It will be removed for both of you.', yes: 'Unsend', danger: true);
    if (!ok) return;
    try {
      await Api.unsend(m.id);
      _load(quiet: true);
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    }
  }

  void _options(Message m) {
    if (m.pending || m.deleted) return;
    final mine = m.senderId == myId;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClayButton(label: 'React', icon: 'heart', tone: ClayTone.soft, onPressed: () {
              Navigator.pop(ctx);
              _react(m);
            }),
            const SizedBox(height: 10),
            ClayButton(label: 'Reply', icon: 'reply', tone: ClayTone.soft, onPressed: () {
              Navigator.pop(ctx);
              setState(() => _replyTo = m);
            }),
            if (mine) ...[
              const SizedBox(height: 10),
              ClayButton(label: 'Unsend', icon: 'trash', tone: ClayTone.soft, onPressed: () {
                Navigator.pop(ctx);
                _unsend(m);
              }),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.other;
    final lastMineIdx = _msgs.lastIndexWhere((m) => m.senderId == myId && !m.pending && !m.deleted);
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.embedded ? null : IconButton(icon: const HIcon('back'), onPressed: () => Navigator.maybePop(context)),
        titleSpacing: widget.embedded ? 16 : 0,
        title: Row(children: [
          Avatar(url: o.avatarUrl, name: o.display, size: 36),
          const SizedBox(width: 10),
          Expanded(child: Text(o.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _msgs.isEmpty
                  ? Failed(message: _error!, onRetry: _load)
                  : _msgs.isEmpty
                      ? Empty(icon: 'chat', title: 'Say hello to ${o.display}', subtitle: 'Your messages will show up here.')
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          itemCount: _msgs.length,
                          itemBuilder: (_, i) {
                            final idx = _msgs.length - 1 - i;
                            final m = _msgs[idx];
                            final seen = idx == lastMineIdx && _otherReadAt != null && !_otherReadAt!.isBefore(m.createdAt);
                            return _Bubble(
                              message: m,
                              mine: m.senderId == myId,
                              seen: seen,
                              onLongPress: () => _options(m),
                              onDoubleTap: () => _react(m),
                            );
                          },
                        ),
        ),
        if (_replyTo != null)
          Container(
            color: C.sunken,
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              const HIcon('reply', size: 18, color: C.honeyDeep),
              const SizedBox(width: 8),
              Expanded(child: Text(_replyTo!.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.inkSoft))),
              IconButton(icon: const HIcon('close', size: 18, color: C.inkSoft), onPressed: () => setState(() => _replyTo = null)),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: ClayField(
                  controller: _input,
                  hint: 'Message',
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 10),
              ClayIconButton(icon: 'send_fill', color: Colors.white, bg: C.honeyDeep, onTap: _send),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.seen, required this.onLongPress, required this.onDoubleTap});
  final Message message;
  final bool mine;
  final bool seen;
  final VoidCallback onLongPress;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final fg = mine ? Colors.white : C.ink;
    final reactions = m.reactions.entries.where((e) => e.value > 0).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        GestureDetector(
          onLongPress: onLongPress,
          onDoubleTap: onDoubleTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76 > 460 ? 460 : MediaQuery.sizeOf(context).width * .76),
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: EdgeInsets.only(bottom: reactions.isEmpty ? 0 : 10),
                decoration: BoxDecoration(
                  color: m.deleted ? C.sunken : (mine ? C.honeyDeep : C.surface),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(mine ? 20 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 20),
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (m.replyTo != null && !m.deleted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: mine ? Colors.white70 : C.honey, width: 3))),
                      child: Text(m.replyTo!.deleted ? 'Message unsent' : m.replyTo!.body,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: .8))),
                    ),
                  Text(
                    m.deleted ? 'Message unsent' : m.body,
                    style: TextStyle(color: m.deleted ? C.inkSoft : fg, fontSize: 15.5, height: 1.3, fontStyle: m.deleted ? FontStyle.italic : FontStyle.normal),
                  ),
                ]),
              ),
              if (reactions.isNotEmpty)
                Positioned(
                  bottom: -2,
                  right: mine ? 8 : null,
                  left: mine ? null : 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.sunken)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final e in reactions) ReactionImg(e.key, size: 15),
                      if (m.reactions.values.fold<int>(0, (a, b) => a + b) > 1) ...[
                        const SizedBox(width: 3),
                        Text('${m.reactions.values.fold<int>(0, (a, b) => a + b)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
          child: Text(m.pending ? 'Sending…' : (seen ? 'Seen · ${ago(m.createdAt)}' : ago(m.createdAt)), style: const TextStyle(fontSize: 11, color: C.inkSoft)),
        ),
      ]),
    );
  }
}
