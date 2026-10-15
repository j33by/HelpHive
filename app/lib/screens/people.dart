import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/friend_actions.dart';
import 'profile.dart';
import '../layout.dart';

class PeopleTab extends StatefulWidget {
  const PeopleTab({super.key});
  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final List<Person> _people = [];
  String _filter = 'all';
  int _requests = 0;
  bool _loading = true;
  bool _more = false;
  bool _loadingMore = false;
  String? _error;
  Timer? _debounce;
  static const _page = 40;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _people.isEmpty;
      _error = null;
    });
    try {
      final list = await Data.people(filter: _filter, query: _search.text, limit: _page);
      Data.people(filter: 'requests', limit: 100).then((r) {
        if (mounted) setState(() => _requests = r.length);
      }).catchError((_) {});
      if (!mounted) return;
      setState(() {
        _people
          ..clear()
          ..addAll(list);
        _more = list.length >= _page;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_more) return;
    _loadingMore = true;
    try {
      final list = await Data.people(filter: _filter, query: _search.text, limit: _page, offset: _people.length);
      if (!mounted) return;
      setState(() {
        final seen = _people.map((p) => p.id).toSet();
        _people.addAll(list.where((p) => !seen.contains(p.id)));
        _more = list.length >= _page;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  void _setFilter(String f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _people.clear();
    });
    _load();
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(builder: (context, box) {
        const hPad = 20.0, gap = 16.0;
        // 2 columns on a phone, up to 4 on a wide window
        final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 640 ? 3 : 2);
        final cardW = (box.maxWidth - hPad * 2 - gap * (cols - 1)) / cols;
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
        // the card height follows its width and the text size
        final double extent = ((cardW * 1.05 + 74).clamp(210.0, 300.0) + (scale - 1) * 70).toDouble();
        return RefreshIndicator(
          color: C.honeyDeep,
          backgroundColor: C.surface,
          onRefresh: _load,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(hPad, 12, hPad, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('People', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -.4)),
                    const SizedBox(height: 14),
                    ClayField(controller: _search, hint: 'Find someone by name', icon: 'search', onChanged: _onQuery, textInputAction: TextInputAction.search),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(children: [
                        Chip2(label: 'Everyone', selected: _filter == 'all', onTap: () => _setFilter('all')),
                        const SizedBox(width: 10),
                        Chip2(label: 'Friends', selected: _filter == 'friends', onTap: () => _setFilter('friends')),
                        const SizedBox(width: 10),
                        Chip2(label: 'Requests', selected: _filter == 'requests', count: _requests, onTap: () => _setFilter('requests')),
                        const SizedBox(width: 10),
                        Chip2(label: 'Sent', selected: _filter == 'sent', onTap: () => _setFilter('sent')),
                        const SizedBox(width: 6),
                      ]),
                    ),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (_error != null && _people.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Failed(message: _error!, onRetry: _load))
              else if (_people.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Empty(
                    icon: 'people',
                    title: switch (_filter) {
                      'friends' => 'No friends yet',
                      'requests' => 'No pending requests',
                      'sent' => 'No requests sent',
                      _ => 'Nobody found',
                    },
                    subtitle: _filter == 'all' ? 'Try a different name.' : 'Head to Everyone to find neighbours.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(hPad, 8, hPad, 24),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: gap,
                      crossAxisSpacing: gap,
                      mainAxisExtent: extent,
                    ),
                    itemCount: _people.length,
                    itemBuilder: (context, i) {
                      final p = _people[i];
                      return _PersonCard(
                        key: ValueKey(p.id),
                        person: p,
                        onChanged: (rel, fid) {
                          setState(() {
                            p.relation = rel;
                            p.friendshipId = fid;
                            if (_filter == 'requests' && rel != 'received') _people.remove(p);
                            if (_filter == 'sent' && rel != 'sent') _people.remove(p);
                            if (_filter == 'friends' && rel != 'friends') _people.remove(p);
                          });
                          Data.people(filter: 'requests', limit: 100).then((r) {
                            if (mounted) setState(() => _requests = r.length);
                          }).catchError((_) {});
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({super.key, required this.person, required this.onChanged});
  final Person person;
  final void Function(String, String?) onChanged;
  @override
  Widget build(BuildContext context) {
    final p = person;
    return ClayCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      onTap: () => Navigator.push(context, appRoute(ProfileScreen(userId: p.id))),
      child: Column(children: [
        Avatar(url: p.avatarUrl, name: p.display, size: 68),
        const SizedBox(height: 10),
        Text(p.display, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text('@${p.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.inkSoft, fontSize: 12.5)),
        const SizedBox(height: 4),
        Expanded(
          child: Text(
            p.bio.isEmpty ? '' : p.bio,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.inkSoft, fontSize: 12, height: 1.3),
          ),
        ),
        FriendActions(userId: p.id, relation: p.relation, friendshipId: p.friendshipId, compact: true, onChanged: onChanged),
      ]),
    );
  }
}
