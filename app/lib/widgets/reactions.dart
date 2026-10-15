import 'package:flutter/material.dart';
import '../theme.dart';
import 'clay.dart';

const reactionLabels = {'like': 'Like', 'love': 'Love', 'haha': 'Haha', 'wow': 'Wow', 'sad': 'Sad'};

class ReactionImg extends StatelessWidget {
  const ReactionImg(this.kind, {super.key, this.size = 22});
  final String kind;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset('assets/icons/reaction_$kind.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

/// Returns a reaction kind, '' to remove the current one, or null if dismissed.
Future<String?> pickReaction(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: clayDeco(radius: 36, depth: .6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final k in reactionLabels.keys)
                  Press(
                    onTap: () => Navigator.pop(ctx, k),
                    scale: 1.12,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: current == k ? BoxDecoration(color: C.honeyPale, shape: BoxShape.circle) : null,
                      child: ReactionImg(k, size: 40),
                    ),
                  ),
              ],
            ),
          ),
          if (current != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Remove my reaction', style: TextStyle(color: C.inkSoft, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    ),
  );
}

class ImageViewer extends StatelessWidget {
  const ImageViewer({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(icon: const HIcon('close', color: Colors.white), onPressed: () => Navigator.pop(context)),
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(url, fit: BoxFit.contain, loadingBuilder: (c, w, p) => p == null ? w : const CircularProgressIndicator()),
          ),
        ),
      );
}
