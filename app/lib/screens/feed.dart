import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/post_card.dart';
import 'compose.dart';
import 'search.dart';
import '../layout.dart';

class FeedTab extends StatefulWidget {
  const FeedTab({super.key});
  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final _scroll = ScrollController();
  final List<Post> _posts = [];
  String? _category;
  bool _loading = true;
  bool _more = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _posts.isEmpty;
      _error = null;
    });
    try {
      final page = await Data.feed(category: _category);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _more = page.hasMore;
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
    if (_loadingMore || !_more || _posts.isEmpty) return;
    _loadingMore = true;
    try {
      final page = await Data.feed(category: _category, before: _posts.last.createdAt);
      if (!mounted) return;
      setState(() {
        final seen = _posts.map((p) => p.id).toSet();
        _posts.addAll(page.posts.where((p) => !seen.contains(p.id)));
        _more = page.hasMore;
      });
    } catch (_) {
      // next scroll will retry
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _compose() async {
    final posted = await Navigator.push<bool>(context, appRoute(const ComposeScreen()));
    if (posted == true) {
      _load();
      AppState.I.refreshMe();
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _setCategory(String? c) {
    if (_category == c) return;
    setState(() {
      _category = c;
      _posts.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = AppState.I.me;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: C.honeyDeep,
        backgroundColor: C.surface,
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Image.asset('assets/icons/bee.png', width: 34, height: 34),
                    const SizedBox(width: 10),
                    const Text('HelpHive', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.4)),
                  ]),
                  const SizedBox(height: 14),
                  Press(
                    onTap: () => Navigator.push(context, appRoute(const SearchScreen())),
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: sunkenDeco(radius: 26),
                      child: Row(children: const [
                        HIcon('search', size: 20, color: C.inkSoft),
                        SizedBox(width: 12),
                        Text('Search people and posts', style: TextStyle(color: C.inkSoft, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClayCard(
                    onTap: _compose,
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Avatar(url: me?.avatarUrl, name: me?.display ?? '', size: 42),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Need a hand, or got one to give?', style: TextStyle(color: C.inkSoft, fontWeight: FontWeight.w600))),
                      const HIcon('image', size: 22, color: C.honeyDeep),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(children: [
                      Chip2(label: 'All', selected: _category == null, onTap: () => _setCategory(null)),
                      const SizedBox(width: 10),
                      Chip2(label: 'Needs help', selected: _category == 'request', onTap: () => _setCategory('request')),
                      const SizedBox(width: 10),
                      Chip2(label: 'Offers', selected: _category == 'offer', onTap: () => _setCategory('offer')),
                      const SizedBox(width: 10),
                      Chip2(label: 'General', selected: _category == 'general', onTap: () => _setCategory('general')),
                      const SizedBox(width: 6),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _posts.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: Failed(message: _error!, onRetry: _load))
            else if (_posts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Empty(title: 'Nothing here yet', subtitle: 'Be the first to ask for help or offer some.'),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList.separated(
                  itemCount: _posts.length + (_more ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 20),
                  itemBuilder: (context, i) {
                    if (i >= _posts.length) {
                      return const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))));
                    }
                    final p = _posts[i];
                    return PostCard(
                      key: ValueKey(p.id),
                      post: p,
                      onDeleted: () {
                        setState(() => _posts.removeWhere((x) => x.id == p.id));
                        AppState.I.refreshMe();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
