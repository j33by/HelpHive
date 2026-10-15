import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import 'chat.dart';
import '../layout.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});
  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final _search = TextEditingController();
  List<Conversation> _convos = [];
  List<Person> _found = [];
  bool _loading = true;
  bool _searching = false;
  String? _error;
  Timer? _debounce;
  Timer? _poll;

  // desktop split view: the conversation shown next to the list
  bool _split = false;
  String? _openId;
  UserLite? _openUser;

  @override
  void initState() {
    super.initState();
    AppState.I.tab.addListener(_onTab);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (AppState.I.tab.value == 3 && _search.text.isEmpty) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    AppState.I.tab.removeListener(_onTab);
    _debounce?.cancel();
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onTab() {
    if (AppState.I.tab.value == 3) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _error = null);
    try {
      final list = await Api.conversations();
      if (!mounted) return;
      setState(() {
        _convos = list;
        _loading = false;
        _error = null;
      });
      AppState.I.setBadges(messages: list.fold<int>(0, (a, c) => a + c.unread));
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _error = friendly(e);
        _loading = false;
      });
    }
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _found = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final list = await Data.people(query: q, limit: 30);
        if (!mounted || _search.text.trim() != q.trim()) return;
        setState(() {
          _found = list;
          _searching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _searching = false);
        toast(context, friendly(e));
      }
    });
  }

  Future<void> _openChat(UserLite user, {String? id}) async {
    try {
      final convId = id ?? await Api.openConversation(user.id);
      if (!mounted) return;
      if (_split) {
        setState(() {
          _openId = convId;
          _openUser = user;
          _search.clear();
          _found = [];
        });
        _load(quiet: true);
        return;
      }
      await Navigator.push(context, appRoute(ChatScreen(conversationId: convId, other: user)));
      _search.clear();
      setState(() => _found = []);
      _load(quiet: true);
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final split = box.maxWidth >= Bp.split;
      if (split != _split) {
        // not setState: this only changes how the next tap behaves
        _split = split;
      }
      if (!split) return ContentColumn(maxWidth: 720, child: _list());
      return Row(children: [
        SizedBox(width: 360, child: _list()),
        const VerticalDivider(width: 1, thickness: 1, color: C.sunken),
        Expanded(
          child: _openId == null || _openUser == null
              ? const Empty(icon: 'chat', title: 'Pick a conversation', subtitle: 'Choose a chat on the left, or search for someone to say hello.')
              : ChatScreen(key: ValueKey(_openId), conversationId: _openId!, other: _openUser!, embedded: true),
        ),
      ]);
    });
  }

  Widget _list() {
    final q = _search.text.trim();
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Messages', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.4)),
            const SizedBox(height: 14),
            ClayField(controller: _search, hint: 'Search someone to message', icon: 'search', onChanged: _onQuery),
            const SizedBox(height: 14),
          ]),
        ),
        Expanded(
          child: q.isNotEmpty
              ? (_searching
                  ? const Center(child: CircularProgressIndicator())
                  : _found.isEmpty
                      ? Empty(icon: 'search', title: 'No one called "$q"')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: _found.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final p = _found[i];
                            return ClayCard(
                              radius: 22,
                              padding: const EdgeInsets.all(12),
                              onTap: () => _openChat(p.lite),
                              child: Row(children: [
                                Avatar(url: p.avatarUrl, name: p.display, size: 46),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(p.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    Text('@${p.username}', style: const TextStyle(color: C.inkSoft, fontSize: 12.5)),
                                  ]),
                                ),
                                const HIcon('send', size: 20, color: C.honeyDeep),
                              ]),
                            );
                          },
                        ))
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _convos.isEmpty
                      ? Failed(message: _error!, onRetry: _load)
                      : RefreshIndicator(
                          color: C.honeyDeep,
                          backgroundColor: C.surface,
                          onRefresh: _load,
                          child: _convos.isEmpty
                              ? ListView(children: const [SizedBox(height: 60), Empty(icon: 'chat', title: 'No conversations yet', subtitle: 'Search for someone above to say hello.')])
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                                  itemCount: _convos.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (_, i) {
                                    final c = _convos[i];
                                    final unread = c.unread > 0;
                                    final preview = c.lastDeleted ? 'Message unsent' : '${c.lastMine ? 'You: ' : ''}${c.lastBody}';
                                    return ClayCard(
                                      radius: 22,
                                      color: _split && c.id == _openId ? C.honeyPale : C.surface,
                                      padding: const EdgeInsets.all(12),
                                      onTap: () => _openChat(c.user, id: c.id),
                                      child: Row(children: [
                                        Avatar(url: c.user.avatarUrl, name: c.user.display, size: 52),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Row(children: [
                                              Expanded(child: Text(c.user.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                                              Text(ago(c.lastAt), style: TextStyle(color: unread ? C.honeyDeep : C.inkSoft, fontSize: 12, fontWeight: unread ? FontWeight.w800 : FontWeight.w500)),
                                            ]),
                                            const SizedBox(height: 3),
                                            Row(children: [
                                              Expanded(
                                                child: Text(preview,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(color: unread ? C.ink : C.inkSoft, fontWeight: unread ? FontWeight.w800 : FontWeight.w500, fontStyle: c.lastDeleted ? FontStyle.italic : FontStyle.normal)),
                                              ),
                                              if (unread) ...[const SizedBox(width: 8), CountDot(c.unread)],
                                            ]),
                                          ]),
                                        ),
                                      ]),
                                    );
                                  },
                                ),
                        ),
        ),
      ]),
    );
  }
}
