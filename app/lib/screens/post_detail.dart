import 'package:flutter/material.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/post_card.dart';
import '../widgets/reactions.dart';
import 'profile.dart';
import '../layout.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, this.post, this.postId}) : assert(post != null || postId != null);
  final Post? post;
  final String? postId;
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  List<Comment> _comments = [];
  bool _loading = true;
  String? _error;
  Comment? _replyTo;
  Comment? _editing;
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _input.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _post == null ? Data.post(widget.postId!) : Future.value(_post),
        Api.comments(widget.postId ?? _post!.id),
      ]);
      if (!mounted) return;
      final post = results[0] as Post?;
      final comments = results[1] as List<Comment>;
      if (post == null) {
        setState(() {
          _error = 'That post is gone.';
          _loading = false;
        });
        return;
      }
      post.commentCount = comments.length;
      setState(() {
        _post = post;
        _comments = comments;
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

  void _syncCount() => _post?.commentCount = _comments.length;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (_editing != null) {
        final updated = await Api.editComment(_editing!.id, text);
        final i = _comments.indexWhere((c) => c.id == _editing!.id);
        if (i >= 0) {
          _comments[i].body = updated.body;
          _comments[i].edited = true;
        }
      } else {
        final c = await Api.addComment(_post!.id, text, parentId: _replyTo?.id);
        _comments.add(c);
        _syncCount();
      }
      _input.clear();
      _replyTo = null;
      _editing = null;
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Comment c) async {
    final ok = await confirm(context, title: 'Delete comment?', body: 'Replies to it will be removed too.', yes: 'Delete', danger: true);
    if (!ok) return;
    try {
      await Api.deleteComment(c.id);
      setState(() {
        _comments.removeWhere((x) => x.id == c.id || x.parentId == c.id);
        _syncCount();
      });
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    }
  }

  Future<void> _react(Comment c, String? kind) async {
    final prevKind = c.myReaction;
    final prevCount = c.reactionCount;
    setState(() {
      if (prevKind == null && kind != null) c.reactionCount++;
      if (prevKind != null && kind == null) c.reactionCount = (c.reactionCount - 1).clamp(0, 1 << 30);
      c.myReaction = kind;
    });
    try {
      await Api.reactComment(c.id, kind);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        c.myReaction = prevKind;
        c.reactionCount = prevCount;
      });
      toast(context, friendly(e));
    }
  }

  void _startReply(Comment c) {
    setState(() {
      _replyTo = c;
      _editing = null;
      _input.clear();
    });
    _focus.requestFocus();
  }

  void _startEdit(Comment c) {
    setState(() {
      _editing = c;
      _replyTo = null;
      _input.text = c.body;
      _input.selection = TextSelection.collapsed(offset: c.body.length);
    });
    _focus.requestFocus();
  }

  void _cancelCompose() {
    setState(() {
      _replyTo = null;
      _editing = null;
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final roots = _comments.where((c) => c.parentId == null).toList();
    final byParent = <String, List<Comment>>{};
    for (final c in _comments.where((c) => c.parentId != null)) {
      byParent.putIfAbsent(c.parentId!, () => []).add(c);
    }
    final postOwner = _post?.authorId == myId;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(child: ClayIconButton(icon: 'back', size: 40, onTap: () => Navigator.pop(context, true))),
          ),
          title: const Text('Post'),
        ),
        body: Column(children: [
          Expanded(
            child: _loading && _post == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _post == null
                    ? Failed(message: _error!, onRetry: _load)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          PostCard(
                            post: _post!,
                            detail: true,
                            onDeleted: () => Navigator.pop(context, 'deleted'),
                          ),
                          const SizedBox(height: 22),
                          Text(_comments.isEmpty ? 'Comments' : 'Comments · ${_comments.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 12),
                          if (_loading)
                            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                          else if (_comments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text('No comments yet. Say something kind.', textAlign: TextAlign.center, style: TextStyle(color: C.inkSoft)),
                            )
                          else
                            for (final c in roots) ...[
                              _CommentTile(
                                c: c,
                                canDelete: c.user.id == myId || postOwner,
                                onReact: (k) => _react(c, k),
                                onReply: () => _startReply(c),
                                onEdit: () => _startEdit(c),
                                onDelete: () => _delete(c),
                              ),
                              for (final r in byParent[c.id] ?? <Comment>[])
                                Padding(
                                  padding: const EdgeInsets.only(left: 38),
                                  child: _CommentTile(
                                    c: r,
                                    small: true,
                                    canDelete: r.user.id == myId || postOwner,
                                    onReact: (k) => _react(r, k),
                                    onReply: () => _startReply(r),
                                    onEdit: () => _startEdit(r),
                                    onDelete: () => _delete(r),
                                  ),
                                ),
                            ],
                        ],
                      ),
          ),
          if (_post != null) _composer(),
        ]),
      ),
    );
  }

  Widget _composer() {
    final note = _editing != null ? 'Editing your comment' : (_replyTo != null ? 'Replying to ${_replyTo!.user.display}' : null);
    return Container(
      decoration: BoxDecoration(color: C.bg, boxShadow: [BoxShadow(color: C.shadowDark.withValues(alpha: .5), blurRadius: 14, offset: const Offset(0, -4))]),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 6),
                child: Row(children: [
                  Expanded(child: Text(note, style: const TextStyle(color: C.honeyDeep, fontWeight: FontWeight.w800, fontSize: 12.5))),
                  Press(onTap: _cancelCompose, child: const Padding(padding: EdgeInsets.all(4), child: HIcon('close', size: 16, color: C.inkSoft))),
                ]),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: ClayField(
                  controller: _input,
                  focusNode: _focus,
                  hint: 'Write a comment',
                  maxLines: 4,
                  minLines: 1,
                  maxLength: 1000,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 10),
              ClayIconButton(
                icon: _input.text.trim().isEmpty ? 'send' : 'send_fill',
                size: 50,
                bg: _input.text.trim().isEmpty ? C.surface : C.honey,
                onTap: _sending || _input.text.trim().isEmpty ? null : _send,
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.c, required this.onReact, required this.onReply, required this.onEdit, required this.onDelete, required this.canDelete, this.small = false});
  final Comment c;
  final bool small;
  final bool canDelete;
  final ValueChanged<String?> onReact;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final mine = c.user.id == myId;
    final reacted = c.myReaction != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Press(
          onTap: c.user.id.isEmpty ? null : () => Navigator.push(context, appRoute(ProfileScreen(userId: c.user.id))),
          child: Avatar(url: c.user.avatarUrl, name: c.user.display, size: small ? 30 : 36),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(color: C.sunken, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.user.display, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(c.body, style: const TextStyle(height: 1.35, fontSize: 14.5)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Wrap(spacing: 14, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${ago(c.createdAt)}${c.edited ? ' · edited' : ''}', style: const TextStyle(color: C.inkSoft, fontSize: 12)),
                Press(
                  onTap: () => onReact(reacted ? null : 'like'),
                  onLongPress: () async {
                    final k = await pickReaction(context, current: c.myReaction);
                    if (k != null) onReact(k.isEmpty ? null : k);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: reacted
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            ReactionImg(c.myReaction!, size: 15),
                            const SizedBox(width: 4),
                            Text(reactionLabels[c.myReaction]!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.honeyDeep)),
                          ])
                        : const Text('React', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.inkSoft)),
                  ),
                ),
                Press(onTap: onReply, child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Reply', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.inkSoft)))),
                if (mine) Press(onTap: onEdit, child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Edit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.inkSoft)))),
                if (canDelete) Press(onTap: onDelete, child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Delete', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.rose)))),
                if (c.reactionCount > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    ReactionImg(c.myReaction ?? 'like', size: 14),
                    const SizedBox(width: 3),
                    Text('${c.reactionCount}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: C.inkSoft)),
                  ]),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
