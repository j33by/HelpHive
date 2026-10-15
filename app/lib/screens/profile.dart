import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/friend_actions.dart';
import '../widgets/post_card.dart';
import '../widgets/reactions.dart';
import 'chat.dart';
import 'edit_profile.dart';
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
      });
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
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Settings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
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
      ]),
      const SizedBox(height: 54),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.display, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.3)),
          Text('@${p.username}', style: const TextStyle(color: C.inkSoft, fontWeight: FontWeight.w600)),
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
      ),
    ]);
  }

  String _month(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.year}';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => ClayCard(
        radius: 22,
        padding: const EdgeInsets.symmetric(vertical: 14),
        depth: .6,
        child: Column(children: [
          Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: C.inkSoft, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}
