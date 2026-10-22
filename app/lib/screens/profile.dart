import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../badges.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/badge.dart';
import '../widgets/clay.dart';
import '../widgets/friend_actions.dart';
import '../widgets/notif_settings.dart';
import '../widgets/post_card.dart';
import '../widgets/reactions.dart';
import 'chat.dart';
import 'edit_profile.dart';
import 'post_detail.dart';
import '../layout.dart';

/// [userId] null means "me" (the profile tab). Pushed for anyone else.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId});
  final String? userId;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _scroll = ScrollController();
  Profile? _profile;
  final List<Post> _posts = [];
  bool _loading = true;
  bool _more = false;
  bool _loadingMore = false;
  String? _error;

  // 0 = profile, 1 = badges, 2 = resolved comments
  int _tab = 0;
  final List<ResolvedItem> _resolved = [];
  bool _resolvedLoaded = false;
  bool _resolvedLoading = false;
  bool _resolvedMore = false;
  String? _resolvedError;

  bool get _isTab => widget.userId == null;
  String get _id => widget.userId ?? myId;
  bool get _self => _id == myId;

  @override
  void initState() {
    super.initState();
    if (_isTab) AppState.I.tab.addListener(_onTab);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    if (_isTab) AppState.I.tab.removeListener(_onTab);
    _scroll.dispose();
    super.dispose();
  }

  void _onTab() {
    if (AppState.I.tab.value == 4) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _profile == null;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([Data.profile(_id), Data.feed(author: _id)]);
      if (!mounted) return;
      final page = results[1] as PostsPage;
      setState(() {
        _profile = results[0] as Profile;
        _posts
          ..clear()
          ..addAll(page.posts);
        _more = page.hasMore;
        _loading = false;
        _error = null;
        _resolvedLoaded = false;
      });
      if (_tab == 2) _loadResolved();
      if (_self) AppState.I.refreshMe();
    } catch (e) {
      if (!mounted || (quiet && _profile != null)) return;
      setState(() {
        _error = friendly(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_tab == 2) return _loadMoreResolved();
    if (_tab != 0) return;
    if (_loadingMore || !_more || _posts.isEmpty) return;
    _loadingMore = true;
    try {
      final page = await Data.feed(author: _id, before: _posts.last.createdAt);
      if (!mounted) return;
      setState(() {
        final seen = _posts.map((p) => p.id).toSet();
        _posts.addAll(page.posts.where((p) => !seen.contains(p.id)));
        _more = page.hasMore;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  void _setTab(int i) {
    if (_tab == i) return;
    setState(() => _tab = i);
    if (i == 2 && !_resolvedLoaded && !_resolvedLoading) _loadResolved();
  }

  Future<void> _loadResolved() async {
    if (_resolvedLoading) return;
    setState(() {
      _resolvedLoading = true;
      _resolvedError = null;
    });
    try {
      final r = await Api.resolved(_id);
      if (!mounted) return;
      setState(() {
        _resolved
          ..clear()
          ..addAll(r.items);
        _resolvedMore = r.hasMore;
        _resolvedLoaded = true;
        _resolvedLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvedError = friendly(e);
        _resolvedLoading = false;
      });
    }
  }

  Future<void> _loadMoreResolved() async {
    if (_resolvedLoading || !_resolvedMore || _resolved.isEmpty) return;
    _resolvedLoading = true;
    try {
      final r = await Api.resolved(_id, before: _resolved.last.helpfulAt);
      if (!mounted) return;
      setState(() {
        final seen = _resolved.map((x) => x.commentId).toSet();
        _resolved.addAll(r.items.where((x) => !seen.contains(x.commentId)));
        _resolvedMore = r.hasMore;
      });
    } catch (_) {
    } finally {
      _resolvedLoading = false;
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(context, appRoute(EditProfileScreen(profile: _profile!)));
    if (saved == true) _load(quiet: true);
  }

  Future<void> _message() async {
    final p = _profile!;
    try {
      final id = await Api.openConversation(p.id);
      if (!mounted) return;
      Navigator.push(context, appRoute(ChatScreen(conversationId: id, other: UserLite(id: p.id, username: p.username, fullName: p.fullName, avatarUrl: p.avatarUrl))));
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    }
  }

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Settings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            const NotifSettings(),
            ClayButton(
              label: 'Sign out',
              icon: 'logout',
              tone: ClayTone.soft,
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await confirm(context, title: 'Sign out?', body: 'You can sign back in any time.', yes: 'Sign out');
                if (ok) await sb.auth.signOut();
              },
            ),
            const SizedBox(height: 12),
            ClayButton(
              label: 'Delete my account',
              icon: 'trash',
              tone: ClayTone.danger,
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await confirm(
                  context,
                  title: 'Delete your account?',
                  body: 'Your profile, posts, photos, comments and messages are erased for good. This cannot be undone.',
                  yes: 'Delete forever',
                  danger: true,
                );
                if (!ok || !mounted) return;
                try {
                  await Api.deleteAccount();
                  await sb.auth.signOut();
                } catch (e) {
                  if (mounted) toast(context, friendly(e));
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      body: ContentColumn(
        maxWidth: 720,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && p == null
              ? SafeArea(child: Stack(children: [Failed(message: _error!, onRetry: _load), if (!_isTab) _backButton()]))
              : RefreshIndicator(
                  color: C.honeyDeep,
                  backgroundColor: C.surface,
                  edgeOffset: 40,
                  onRefresh: _load,
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _header(p!)),
                      SliverToBoxAdapter(child: _navBar(p)),
                      if (_tab == 0)
                        ..._profileSlivers(p)
                      else if (_tab == 1)
                        ..._badgeSlivers(p)
                      else
                        ..._resolvedSlivers(p),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _backButton() => Positioned(
        left: 16,
        top: 12,
        child: ClayIconButton(icon: 'back', size: 42, onTap: () => Navigator.pop(context)),
      );

  Widget _header(Profile p) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(clipBehavior: Clip.none, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Container(
              height: 176,
              width: double.infinity,
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [C.honeyPale, C.honey])),
              child: p.coverUrl == null
                  ? Opacity(opacity: .35, child: Center(child: Image.asset('assets/icons/hex_cell.png', width: 90, color: Colors.white, colorBlendMode: BlendMode.srcIn)))
                  : Press(
                      scale: 1,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewer(url: p.coverUrl!))),
                      child: CachedNetworkImage(imageUrl: p.coverUrl!, fit: BoxFit.cover, placeholder: (_, __) => const SizedBox()),
                    ),
            ),
          ),
        ),
        if (!_isTab) Positioned(left: 28, top: top + 20, child: ClayIconButton(icon: 'back', size: 40, onTap: () => Navigator.pop(context))),
        if (_isTab) Positioned(right: 28, top: top + 20, child: ClayIconButton(icon: 'settings', size: 40, onTap: _settings)),
        Positioned(
          left: 32,
          bottom: -44,
          child: Avatar(url: p.avatarUrl, name: p.display, size: 96),
        ),
        // the badge they wear, shining on the corner of their picture
        if (p.badge != null) Positioned(left: 89, bottom: -45, child: BadgeEmblem(p.badge!, size: 46)),
      ]),
      const SizedBox(height: 54),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.display, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.3)),
          Text('@${p.username}', style: const TextStyle(color: C.inkSoft, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _starsRow(p),
        ]),
      ),
    ]);
  }


  Widget _starsRow(Profile p) {
    final tier = p.badge;
    return Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      StarCount(p.stars, size: 15),
      if (tier != null)
        BadgeChip(tier, onTap: () => _setTab(1))
      else
        const Text('No badge yet', style: TextStyle(color: C.inkSoft, fontWeight: FontWeight.w700, fontSize: 13)),
    ]);
  }

  /// The small nav under the picture: Profile | Badges | Resolved.
  Widget _navBar(Profile p) {
    final earned = badgeTiers.where((t) => p.stars >= t.min).length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: Row(children: [
          _NavPill(label: 'Profile', selected: _tab == 0, onTap: () => _setTab(0)),
          const SizedBox(width: 8),
          _NavPill(label: 'Badges', count: earned, selected: _tab == 1, onTap: () => _setTab(1)),
          const SizedBox(width: 8),
          _NavPill(label: 'Resolved', count: p.stars, selected: _tab == 2, onTap: () => _setTab(2)),
        ]),
      ),
    );
  }

  Widget _about(Profile p) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (p.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.bio, style: const TextStyle(fontSize: 15, height: 1.4)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 6, children: [
            if (p.location.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const HIcon('pin', size: 16, color: C.inkSoft),
                const SizedBox(width: 5),
                Text(p.location, style: const TextStyle(color: C.inkSoft, fontWeight: FontWeight.w600, fontSize: 13.5)),
              ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const HIcon('hex_cell', size: 16, color: C.inkSoft),
              const SizedBox(width: 5),
              Text('In the hive since ${_month(p.createdAt)}', style: const TextStyle(color: C.inkSoft, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ]),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _Stat(value: p.postsCount, label: 'Posts')),
            const SizedBox(width: 14),
            Expanded(child: _Stat(value: p.friendsCount, label: 'Friends')),
            const SizedBox(width: 14),
            Expanded(child: _Stat(value: p.stars, label: 'Stars', star: true)),
          ]),
          const SizedBox(height: 18),
          if (_self)
            ClayButton(label: 'Edit profile', icon: 'edit', onPressed: _edit)
          else ...[
            FriendActions(
              userId: p.id,
              relation: p.relation,
              friendshipId: p.friendshipId,
              onChanged: (rel, fid) {
                final wasFriend = p.relation == 'friends';
                setState(() {
                  p.relation = rel;
                  p.friendshipId = fid;
                  if (rel == 'friends' && !wasFriend) p.friendsCount++;
                  if (rel != 'friends' && wasFriend) p.friendsCount = (p.friendsCount - 1).clamp(0, 1 << 30);
                });
              },
            ),
            const SizedBox(height: 12),
            ClayButton(label: 'Message', icon: 'chat', tone: ClayTone.soft, onPressed: _message),
          ],
        ]),
      );

  List<Widget> _profileSlivers(Profile p) => [
        SliverToBoxAdapter(child: _about(p)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                          child: Text(_self ? 'Your posts' : 'Posts', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      if (_posts.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Empty(icon: 'pin', title: _self ? 'Nothing posted yet' : 'No posts yet', subtitle: _self ? 'Your requests and offers will live here.' : null),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                          sliver: SliverList.separated(
                            itemCount: _posts.length + (_more ? 1 : 0),
                            separatorBuilder: (_, __) => const SizedBox(height: 20),
                            itemBuilder: (_, i) {
                              if (i >= _posts.length) {
                                return const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))));
                              }
                              final post = _posts[i];
                              return PostCard(
                                key: ValueKey(post.id),
                                post: post,
                                onDeleted: () {
                                  setState(() {
                                    _posts.removeWhere((x) => x.id == post.id);
                                    p.postsCount = (p.postsCount - 1).clamp(0, 1 << 30);
                                  });
                                },
                              );
                            },
                          ),
                        ),
      ];

  // ---------------------------------------------------------------- badges tab
  List<Widget> _badgeSlivers(Profile p) {
    final tier = p.badge;
    final next = nextBadge(p.stars);
    final lower = tier?.min ?? 0;
    final frac = next == null ? 1.0 : ((p.stars - lower) / (next.min - lower)).clamp(0.0, 1.0).toDouble();
    final left = next == null ? 0 : next.min - p.stars;

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        sliver: SliverToBoxAdapter(
          child: ClayCard(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            child: Column(children: [
              BadgeEmblem(tier ?? badgeTiers.first, size: 136, locked: tier == null),
              const SizedBox(height: 14),
              Text(tier?.name ?? 'No badge yet', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                tier != null
                    ? '“${tier.quote}”'
                    : (_self ? 'Get your first star to earn ${badgeTiers.first.name}.' : '${p.display} has not earned a badge yet.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.35, color: C.inkSoft, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              StarCount(p.stars, size: 18),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: frac, minHeight: 10, backgroundColor: C.sunken, color: C.honey),
              ),
              const SizedBox(height: 8),
              Text(
                next == null
                    ? (_self ? 'You reached the top of the hive!' : 'Reached the top of the hive!')
                    : '$left more star${left == 1 ? '' : 's'} to unlock ${next.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: C.honeyDeep),
              ),
              if (_self) ...[
                const SizedBox(height: 10),
                const Text(
                  'You earn a star each time the person you helped marks your comment as helpful.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.inkSoft, fontSize: 12.5, height: 1.35),
                ),
              ],
            ]),
          ),
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 10),
        sliver: SliverToBoxAdapter(child: Text('All badges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        sliver: SliverList.separated(
          itemCount: badgeTiers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) {
            final t = badgeTiers[i];
            return _BadgeRow(tier: t, earned: p.stars >= t.min, current: t.key == tier?.key);
          },
        ),
      ),
    ];
  }

  // ------------------------------------------------------------- resolved tab
  List<Widget> _resolvedSlivers(Profile p) {
    final title = SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      sliver: SliverToBoxAdapter(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_self ? 'Your resolved comments' : 'Resolved comments', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          const Text('Answers the person who asked marked as helpful.', style: TextStyle(color: C.inkSoft, fontSize: 13.5)),
        ]),
      ),
    );

    if (_resolvedError != null && _resolved.isEmpty) {
      return [title, SliverToBoxAdapter(child: SizedBox(height: 240, child: Failed(message: _resolvedError!, onRetry: _loadResolved)))];
    }
    if (!_resolvedLoaded) {
      return [title, const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())))];
    }
    if (_resolved.isEmpty) {
      return [
        title,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Empty(
              icon: 'check_circle',
              title: _self ? 'No resolved comments yet' : 'Nothing resolved yet',
              subtitle: _self ? 'When someone marks your comment as helpful, it shows up here with their post.' : null,
            ),
          ),
        ),
      ];
    }
    return [
      title,
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        sliver: SliverList.separated(
          itemCount: _resolved.length + (_resolvedMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 18),
          itemBuilder: (_, i) {
            if (i >= _resolved.length) {
              return const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))));
            }
            final item = _resolved[i];
            return _ResolvedCard(
              item: item,
              onTap: () => Navigator.push(context, appRoute(PostDetailScreen(postId: item.postId))).then((_) {
                if (mounted) _load(quiet: true);
              }),
            );
          },
        ),
      ),
    ];
  }

  String _month(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.year}';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.star = false});
  final int value;
  final String label;
  final bool star;
  @override
  Widget build(BuildContext context) => ClayCard(
        radius: 22,
        padding: const EdgeInsets.symmetric(vertical: 14),
        depth: .6,
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (star) ...[const Icon(Icons.star_rounded, size: 22, color: C.honey), const SizedBox(width: 2)],
            Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ]),
          Text(label, style: const TextStyle(color: C.inkSoft, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}

class _NavPill extends StatelessWidget {
  const _NavPill({required this.label, required this.selected, required this.onTap, this.count = 0});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int count;
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: selected ? clayDeco(color: C.honey, radius: 18, depth: .35) : clayDeco(color: C.surface, radius: 18, depth: .25),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: selected ? C.ink : C.inkSoft)),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: selected ? Colors.white.withValues(alpha: .55) : C.honeyPale, borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5, color: selected ? C.ink : C.honeyDeep)),
              ),
            ],
          ]),
        ),
      );
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.tier, required this.earned, required this.current});
  final BadgeTier tier;
  final bool earned;
  final bool current;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: earned ? 1 : .65,
        child: ClayCard(
          radius: 22,
          depth: .5,
          padding: const EdgeInsets.all(14),
          color: current ? C.honeyPale : C.surface,
          child: Row(children: [
            BadgeEmblem(tier, size: 70, locked: !earned, animate: earned),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(tier.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
                  if (current) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: C.honey, borderRadius: BorderRadius.circular(10)),
                      child: const Text('Wearing', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: C.ink)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text('“${tier.quote}”', style: const TextStyle(fontSize: 13.5, height: 1.3, color: C.inkSoft, fontStyle: FontStyle.italic)),
                const SizedBox(height: 7),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(earned ? Icons.star_rounded : Icons.lock_rounded, size: 15, color: earned ? C.honey : C.inkSoft),
                  const SizedBox(width: 4),
                  Text(
                    earned ? 'Earned at ${tier.min} star${tier.min == 1 ? '' : 's'}' : 'Unlocks at ${tier.min} star${tier.min == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: earned ? C.honeyDeep : C.inkSoft),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      );
}

class _ResolvedCard extends StatelessWidget {
  const _ResolvedCard({required this.item, required this.onTap});
  final ResolvedItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final body = item.postBody.trim();
    return ClayCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(url: item.author.avatarUrl, name: item.author.display, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Asked by ${item.author.display}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              Text(ago(item.postCreatedAt), style: const TextStyle(color: C.inkSoft, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          CategoryTag(item.category),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.sunken, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (body.isNotEmpty) Text(body, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, height: 1.35)),
            if (item.hasImage)
              Padding(
                padding: EdgeInsets.only(top: body.isEmpty ? 0 : 6),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  HIcon('image', size: 14, color: C.inkSoft),
                  SizedBox(width: 5),
                  Text('Photo attached', style: TextStyle(color: C.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: helpfulDeco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HelpfulTag(),
            const SizedBox(height: 8),
            Text(item.commentBody, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, height: 1.35)),
            const SizedBox(height: 6),
            Text('Marked helpful · ${ago(item.helpfulAt)}', style: const TextStyle(color: C.honeyDeep, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }
}
