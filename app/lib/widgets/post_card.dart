import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../screens/compose.dart';
import '../screens/post_detail.dart';
import '../screens/profile.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import 'badge.dart';
import 'clay.dart';
import 'reactions.dart';
import '../layout.dart';

class CategoryTag extends StatelessWidget {
  const CategoryTag(this.category, {super.key});
  final String category;
  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, icon) = switch (category) {
      'request' => ('Needs help', const Color(0xFFFADBD2), C.rose, 'cat_request'),
      'offer' => ('Offering help', const Color(0xFFD9EBDD), C.sage, 'cat_offer'),
      _ => ('General', C.sunken, C.inkSoft, 'cat_general'),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        HIcon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: fg)),
      ]),
    );
  }
}

/// The comment the poster marked helpful, previewed on the feed card.
class _HelpfulAnswer extends StatelessWidget {
  const _HelpfulAnswer(this.h);
  final HelpfulPreview h;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: helpfulDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const HelpfulTag(),
          const SizedBox(height: 8),
          NameLine(name: h.user.display, stars: h.user.stars, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 2),
          Text(h.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.35)),
        ]),
      );
}

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post, this.detail = false, this.onDeleted, this.onChanged});
  final Post post;
  final bool detail;
  final VoidCallback? onDeleted;
  final VoidCallback? onChanged;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  Post get p => widget.post;
  bool get mine => p.authorId == myId;

  Future<void> _react(String? kind) async {
    final prevKind = p.myReaction;
    final prevCount = p.reactionCount;
    setState(() {
      if (prevKind == null && kind != null) p.reactionCount++;
      if (prevKind != null && kind == null) p.reactionCount = (p.reactionCount - 1).clamp(0, 1 << 30);
      p.myReaction = kind;
    });
    try {
      await Data.react(p.id, kind);
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        p.myReaction = prevKind;
        p.reactionCount = prevCount;
      });
      toast(context, friendly(e));
    }
  }

  Future<void> _longPressReact() async {
    final k = await pickReaction(context, current: p.myReaction);
    if (k == null) return;
    _react(k.isEmpty ? null : k);
  }

  void _openDetail() {
    if (widget.detail) return;
    Navigator.push<Object?>(context, appRoute(PostDetailScreen(post: p))).then((r) {
      if (r == 'deleted') {
        widget.onDeleted?.call();
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  void _openProfile() {
    Navigator.push(context, appRoute(ProfileScreen(userId: p.authorId)));
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'edit':
        final changed = await Navigator.push<bool>(context, appRoute(ComposeScreen(editing: p)));
        if (changed == true) {
          final fresh = await Data.post(p.id);
          if (fresh != null && mounted) {
            setState(() {
              p.body = fresh.body;
              p.category = fresh.category;
              p.imagePath = fresh.imagePath;
              p.imageUrl = fresh.imageUrl;
              p.updatedAt = fresh.updatedAt;
            });
          }
          widget.onChanged?.call();
        }
      case 'resolve':
        try {
          await Data.setResolved(p, !p.isResolved);
          if (mounted) setState(() {});
          widget.onChanged?.call();
        } catch (e) {
          if (mounted) toast(context, friendly(e));
        }
      case 'delete':
        final ok = await confirm(context, title: 'Delete this post?', body: 'The photo and all comments go with it. This cannot be undone.', yes: 'Delete', danger: true);
        if (!ok) return;
        try {
          await Api.deletePost(p.id);
          widget.onDeleted?.call();
        } catch (e) {
          if (mounted) toast(context, friendly(e));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reacted = p.myReaction != null;
    return ClayCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      onTap: widget.detail ? null : _openDetail,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Press(onTap: _openProfile, child: Avatar(url: p.avatarUrl, name: p.display, size: 44)),
          const SizedBox(width: 12),
          Expanded(
            child: Press(
              onTap: _openProfile,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NameLine(name: p.display, stars: p.authorStars, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('@${p.username} · ${ago(p.createdAt)}${p.edited ? ' · edited' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.inkSoft, fontSize: 12.5)),
              ]),
            ),
          ),
          if (mine)
            PopupMenuButton<String>(
              onSelected: _menu,
              color: C.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              icon: const HIcon('more', size: 22, color: C.inkSoft),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit post', style: TextStyle(fontWeight: FontWeight.w700))),
                PopupMenuItem(value: 'resolve', child: Text(p.isResolved ? 'Reopen' : 'Mark as resolved', style: const TextStyle(fontWeight: FontWeight.w700))),
                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(fontWeight: FontWeight.w700, color: C.rose))),
              ],
            ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          CategoryTag(p.category),
          if (p.isResolved)
            Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
              decoration: BoxDecoration(color: C.honeyPale, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                HIcon('check', size: 13, color: C.honeyDeep),
                SizedBox(width: 4),
                Text('Resolved', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: C.honeyDeep)),
              ]),
            ),
        ]),
        if (p.body.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(p.body, style: const TextStyle(fontSize: 15.5, height: 1.4), maxLines: widget.detail ? null : 8, overflow: widget.detail ? null : TextOverflow.ellipsis),
        ],
        if (p.imageUrl != null) ...[
          const SizedBox(height: 12),
          Press(
            scale: .99,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewer(url: p.imageUrl!))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: CachedNetworkImage(
                  imageUrl: p.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(height: 220, color: C.sunken),
                  errorWidget: (_, __, ___) => Container(height: 120, color: C.sunken, alignment: Alignment.center, child: const Text('Picture unavailable', style: TextStyle(color: C.inkSoft))),
                ),
              ),
            ),
          ),
        ],
        // the poster starred an answer: show it right here so anyone with the same problem sees it
        if (!widget.detail && p.helpful != null) ...[
          const SizedBox(height: 12),
          _HelpfulAnswer(p.helpful!),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Press(
            onTap: () => _react(reacted ? null : 'like'),
            onLongPress: _longPressReact,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: reacted ? BoxDecoration(color: C.honeyPale, borderRadius: BorderRadius.circular(16)) : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                reacted ? ReactionImg(p.myReaction!, size: 22) : const HIcon('heart', size: 22, color: C.inkSoft),
                const SizedBox(width: 7),
                Text(p.reactionCount == 0 ? 'React' : '${p.reactionCount}',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: reacted ? C.honeyDeep : C.inkSoft)),
              ]),
            ),
          ),
          const SizedBox(width: 4),
          Press(
            onTap: widget.detail ? null : _openDetail,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const HIcon('comment', size: 22, color: C.inkSoft),
                const SizedBox(width: 7),
                Text(p.commentCount == 0 ? 'Comment' : '${p.commentCount}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: C.inkSoft)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}
