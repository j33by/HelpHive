import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/pick.dart';

/// New post, or edit one of mine when [editing] is given. Pops with true when saved.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.editing});
  final Post? editing;
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final TextEditingController _body = TextEditingController(text: widget.editing?.body ?? '');
  late String _category = widget.editing?.category ?? 'general';
  Picked? _image;
  bool _removeExisting = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _hasImage => _image != null || (!_removeExisting && widget.editing?.imageUrl != null);
  bool get _canPost => !_busy && (_body.text.trim().isNotEmpty || _hasImage);

  Future<void> _pick() async {
    final p = await pickImage(context);
    if (p != null) setState(() => _image = p);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final e = widget.editing;
      if (e == null) {
        await Data.createPost(body: _body.text, category: _category, image: _image?.bytes, ext: _image?.ext);
      } else {
        await Data.updatePost(e,
            body: _body.text, category: _category, removeImage: _removeExisting, newImage: _image?.bytes, ext: _image?.ext);
      }
      AppState.I.refreshMe();
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, friendly(err));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AppState.I.me;
    final existing = widget.editing?.imageUrl;
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(child: ClayIconButton(icon: 'close', size: 40, onTap: () => Navigator.pop(context))),
        ),
        title: Text(widget.editing == null ? 'New post' : 'Edit post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: ClayButton(label: widget.editing == null ? 'Post' : 'Save', small: true, expanded: false, loading: _busy, onPressed: _canPost ? _save : null)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(children: [
              Avatar(url: me?.avatarUrl, name: me?.display ?? '', size: 44),
              const SizedBox(width: 12),
              Text(me?.display ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 18),
            const Text('What is this about?', style: TextStyle(fontWeight: FontWeight.w800, color: C.inkSoft)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _CatTile(label: 'Need help', icon: 'cat_request', on: _category == 'request', onTap: () => setState(() => _category = 'request'))),
              const SizedBox(width: 10),
              Expanded(child: _CatTile(label: 'Offer help', icon: 'cat_offer', on: _category == 'offer', onTap: () => setState(() => _category = 'offer'))),
              const SizedBox(width: 10),
              Expanded(child: _CatTile(label: 'General', icon: 'cat_general', on: _category == 'general', onTap: () => setState(() => _category = 'general'))),
            ]),
            const SizedBox(height: 20),
            ClayField(
              controller: _body,
              hint: _category == 'request'
                  ? 'What do you need, and when?'
                  : _category == 'offer'
                      ? 'What can you help with?'
                      : 'Share something with the hive',
              maxLines: 8,
              minLines: 5,
              maxLength: 2000,
              autofocus: widget.editing == null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, right: 6),
                child: Text('${_body.text.length}/2000', style: const TextStyle(color: C.inkSoft, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 14),
            if (_image != null)
              _Preview(child: Image.memory(_image!.bytes, fit: BoxFit.cover), onRemove: () => setState(() => _image = null))
            else if (existing != null && !_removeExisting)
              _Preview(
                child: CachedNetworkImage(imageUrl: existing, fit: BoxFit.cover),
                onRemove: () => setState(() => _removeExisting = true),
              )
            else
              ClayButton(label: 'Add a photo', icon: 'image', tone: ClayTone.soft, onPressed: _pick),
          ],
        ),
      ),
    );
  }
}

class _CatTile extends StatelessWidget {
  const _CatTile({required this.label, required this.icon, required this.on, required this.onTap});
  final String label;
  final String icon;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: clayDeco(color: on ? C.honey : C.surface, radius: 20, depth: on ? .4 : .55),
          child: Column(children: [
            HIcon(icon, size: 26, color: on ? C.ink : C.inkSoft),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: on ? C.ink : C.inkSoft)),
          ]),
        ),
      );
}

class _Preview extends StatelessWidget {
  const _Preview({required this.child, required this.onRemove});
  final Widget child;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Stack(children: [
        ClipRRect(borderRadius: BorderRadius.circular(22), child: SizedBox(height: 240, width: double.infinity, child: child)),
        Positioned(right: 10, top: 10, child: ClayIconButton(icon: 'close', size: 36, onTap: onRemove)),
      ]);
}
