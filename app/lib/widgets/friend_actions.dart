import 'package:flutter/material.dart';
import '../services/data.dart';
import '../theme.dart';
import 'clay.dart';

/// Add / Cancel / Confirm + Decline / Friends, driven by the relation to a person.
class FriendActions extends StatefulWidget {
  const FriendActions({super.key, required this.userId, required this.relation, required this.friendshipId, required this.onChanged, this.compact = false});
  final String userId;
  final String relation; // none | friends | sent | received
  final String? friendshipId;
  final void Function(String relation, String? friendshipId) onChanged;
  final bool compact;
  @override
  State<FriendActions> createState() => _FriendActionsState();
}

class _FriendActionsState extends State<FriendActions> {
  bool _busy = false;

  Future<void> _run(Future<(String, String?)> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final (rel, fid) = await job();
      widget.onChanged(rel, fid);
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fid = widget.friendshipId;
    final small = widget.compact;
    switch (widget.relation) {
      case 'sent':
        return ClayButton(
          label: 'Cancel',
          icon: 'user_x',
          small: small,
          tone: ClayTone.soft,
          loading: _busy,
          onPressed: fid == null ? null : () => _run(() async {
                await Data.removeFriendship(fid, widget.userId);
                return ('none', null);
              }),
        );
      case 'received':
        final confirmBtn = ClayButton(
          label: 'Confirm',
          icon: 'user_check',
          small: small,
          loading: _busy,
          onPressed: fid == null ? null : () => _run(() async {
                await Data.respond(fid, widget.userId, true);
                return ('friends', fid);
              }),
        );
        final declineAction = fid == null ? null : () => _run(() async {
              await Data.respond(fid, widget.userId, false);
              return ('none', null);
            });
        return Row(children: [
          Expanded(child: confirmBtn),
          const SizedBox(width: 8),
          if (small)
            ClayIconButton(icon: 'close', size: 38, onTap: _busy ? null : declineAction)
          else
            ClayButton(label: 'Decline', tone: ClayTone.soft, expanded: false, onPressed: _busy ? null : declineAction),
        ]);
      case 'friends':
        return ClayButton(
          label: 'Friends',
          icon: 'user_check',
          small: small,
          tone: ClayTone.soft,
          loading: _busy,
          onPressed: fid == null ? null : () async {
            final ok = await confirm(context, title: 'Remove friend?', body: 'You can always send a new request later.', yes: 'Remove', danger: true);
            if (!ok) return;
            _run(() async {
              await Data.removeFriendship(fid, widget.userId);
              return ('none', null);
            });
          },
        );
      default:
        return ClayButton(
          label: 'Add',
          icon: 'user_add',
          small: small,
          loading: _busy,
          onPressed: () => _run(() async {
            final id = await Data.addFriend(widget.userId);
            return ('sent', id);
          }),
        );
    }
  }
}
