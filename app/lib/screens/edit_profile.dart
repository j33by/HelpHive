import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/data.dart';
import '../theme.dart';
import '../widgets/clay.dart';
import '../widgets/pick.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final Profile profile;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.profile.username);
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _bio = TextEditingController(text: widget.profile.bio);
  late final _location = TextEditingController(text: widget.profile.location);
  late String? _avatar = widget.profile.avatarUrl;
  late String? _cover = widget.profile.coverUrl;
  bool _busy = false;
  bool _avatarBusy = false;
  bool _coverBusy = false;
  bool _changed = false;

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _bio.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final p = await pickImage(context, maxWidth: 800);
    if (p == null) return;
    setState(() => _avatarBusy = true);
    try {
      final url = await Data.setPicture(cover: false, bytes: p.bytes, ext: p.ext, oldUrl: _avatar);
      setState(() {
        _avatar = url;
        _changed = true;
      });
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _pickCover() async {
    final p = await pickImage(context, maxWidth: 1600);
    if (p == null) return;
    setState(() => _coverBusy = true);
    try {
      final url = await Data.setPicture(cover: true, bytes: p.bytes, ext: p.ext, oldUrl: _cover);
      setState(() {
        _cover = url;
        _changed = true;
      });
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<void> _removeCover() async {
    setState(() => _coverBusy = true);
    try {
      await Data.clearCover(_cover);
      setState(() {
        _cover = null;
        _changed = true;
      });
    } catch (e) {
      if (mounted) toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await Data.updateProfile(username: _username.text, fullName: _name.text, bio: _bio.text, location: _location.text);
      await AppState.I.refreshMe();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, friendly(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.isEmpty ? widget.profile.username : _name.text;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(child: ClayIconButton(icon: 'back', size: 40, onTap: () => Navigator.pop(context, _changed))),
          ),
          title: const Text('Edit profile'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: ClayButton(label: 'Save', small: true, expanded: false, loading: _busy, onPressed: _save)),
            ),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              SizedBox(
                height: 200,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    bottom: 44,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Container(
                        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [C.honeyPale, C.honey])),
                        child: _cover == null ? null : CachedNetworkImage(imageUrl: _cover!, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Row(children: [
                      if (_cover != null) ...[ClayIconButton(icon: 'trash', size: 40, color: C.rose, onTap: _coverBusy ? null : _removeCover), const SizedBox(width: 10)],
                      ClayIconButton(icon: 'camera', size: 40, onTap: _coverBusy ? null : _pickCover),
                    ]),
                  ),
                  if (_coverBusy) const Positioned.fill(bottom: 44, child: Center(child: CircularProgressIndicator())),
                  Positioned(
                    left: 16,
                    bottom: 0,
                    child: Stack(children: [
                      Avatar(url: _avatar, name: name, size: 88),
                      Positioned(right: 0, bottom: 0, child: ClayIconButton(icon: 'camera', size: 34, bg: C.honey, onTap: _avatarBusy ? null : _pickAvatar)),
                      if (_avatarBusy) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              _label('Name'),
              ClayField(controller: _name, hint: 'Your name', icon: 'user', maxLength: 60, onChanged: (_) => setState(() {}), textInputAction: TextInputAction.next),
              const SizedBox(height: 16),
              _label('Username'),
              ClayField(
                controller: _username,
                hint: 'username',
                icon: 'user',
                maxLength: 24,
                textInputAction: TextInputAction.next,
                validator: (v) => RegExp(r'^[a-zA-Z0-9_.]{3,24}$').hasMatch((v ?? '').trim()) ? null : '3 to 24 letters, numbers, dots or underscores',
              ),
              const SizedBox(height: 16),
              _label('Bio'),
              ClayField(controller: _bio, hint: 'A line or two about you', maxLines: 4, minLines: 3, maxLength: 280),
              const SizedBox(height: 16),
              _label('Location'),
              ClayField(controller: _location, hint: 'Barangay, city or neighbourhood', icon: 'pin', maxLength: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: C.inkSoft, fontSize: 13.5)),
      );
}
