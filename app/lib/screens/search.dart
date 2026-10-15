import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/friend_actions.dart';
import '../widgets/post_card.dart';
import 'profile.dart';
import '../layout.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  bool _posts = false;
  bool _loading = false;
  String? _error;
  String _ran = '';
  List<Person> _people = [];
  List<Post> _postResults = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), _run);
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.isEmpty) {
      setState(() {
        _ran = '';
        _people = [];
        _postResults = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_posts) {
        final page = await Data.feed(search: q);
        if (!mounted || _q.text.trim() != q) return;
        setState(() => _postResults = page.posts);
      } else {
        final list = await Data.people(query: q, limit: 30);
        if (!mounted || _q.text.trim() != q) return;
        setState(() => _people = list);
      }
      setState(() {
        _ran = q;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendly(e);
        _loading = false;
      });
    }
  }

  void _mode(bool posts) {
    if (_posts == posts) return;
    setState(() => _posts = posts);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final empty = _ran.isNotEmpty && !_loading && _error == null && (_posts ? _postResults.isEmpty : _people.isEmpty);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(child: ClayIconButton(icon: 'back', size: 40, onTap: () => Navigator.pop(context))),
        ),
        titleSpacing: 12,
        title: ClayField(controller: _q, hint: 'Search HelpHive', icon: 'search', autofocus: true, onChanged: _onChanged, textInputAction: TextInputAction.search, onSubmitted: (_) => _run()),
        toolbarHeight: 72,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(children: [
            Chip2(label: 'People', selected: !_posts, onTap: () => _mode(false)),
            const SizedBox(width: 10),
            Chip2(label: 'Posts', selected: _posts, onTap: () => _mode(true)),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Failed(message: _error!, onRetry: _run)
                  : _ran.isEmpty
                      ? const Empty(icon: 'search', title: 'Search the hive', subtitle: 'Find neighbours by name or username, or posts by what they say.')
                      : empty
                          ? Empty(icon: 'search', title: 'No matches for "$_ran"')
                          : _posts
                              ? ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                                  itemCount: _postResults.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 20),
                                  itemBuilder: (_, i) => PostCard(
                                    key: ValueKey(_postResults[i].id),
                                    post: _postResults[i],
                                    onDeleted: () => setState(() => _postResults.removeAt(i)),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                                  itemCount: _people.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                                  itemBuilder: (_, i) {
                                    final p = _people[i];
                                    return ClayCard(
                                      padding: const EdgeInsets.all(12),
                                      radius: 22,
                                      onTap: () => Navigator.push(context, appRoute(ProfileScreen(userId: p.id))),
                                      child: Row(children: [
                                        Avatar(url: p.avatarUrl, name: p.display, size: 48),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(p.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                                            Text('@${p.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.inkSoft, fontSize: 12.5)),
                                          ]),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 112,
                                          child: FriendActions(
                                            userId: p.id,
                                            relation: p.relation,
                                            friendshipId: p.friendshipId,
                                            compact: true,
                                            onChanged: (rel, fid) => setState(() {
                                              p.relation = rel;
                                              p.friendshipId = fid;
                                            }),
                                          ),
                                        ),
                                      ]),
                                    );
                                  },
                                ),
        ),
      ]),
    );
  }
}
