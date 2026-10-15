import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import 'clay.dart';

class Picked {
  Picked(this.bytes, this.ext);
  final Uint8List bytes;
  final String ext;
}

/// Asks camera or gallery, shrinks the picture, returns the bytes.
Future<Picked?> pickImage(BuildContext context, {int maxWidth = 1600}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Add a picture', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          ClayButton(label: 'Choose from gallery', icon: 'image', tone: ClayTone.soft, onPressed: () => Navigator.pop(ctx, ImageSource.gallery)),
          const SizedBox(height: 12),
          ClayButton(label: 'Take a photo', icon: 'camera', tone: ClayTone.soft, onPressed: () => Navigator.pop(ctx, ImageSource.camera)),
        ]),
      ),
    ),
  );
  if (source == null) return null;
  try {
    final x = await ImagePicker().pickImage(source: source, maxWidth: maxWidth.toDouble(), imageQuality: 85);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    final name = x.name.toLowerCase();
    final ext = name.endsWith('.png') ? 'png' : (name.endsWith('.webp') ? 'webp' : 'jpg');
    return Picked(bytes, ext);
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open that picture.');
    return null;
  }
}
