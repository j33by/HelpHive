import 'package:flutter/material.dart';
import 'theme.dart';

/// Window widths where the layout changes. They follow the window, not the
/// operating system, so a narrow desktop window falls back to the phone layout.
class Bp {
  /// From here the bottom bar becomes a side bar.
  static const wide = 820.0;

  /// From here the side bar shows labels instead of only icons.
  static const full = 1180.0;

  /// Content width (window minus side bar) where chats show the list and the
  /// open conversation side by side.
  static const split = 880.0;
}

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= Bp.wide;

/// Keeps content at a readable width and centres it. On a phone it does nothing.
class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, required this.child, this.maxWidth = 720});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth <= maxWidth) return child;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: maxWidth,
            height: box.hasBoundedHeight ? box.maxHeight : null,
            child: child,
          ),
        );
      });
}

/// Page route used for every full screen the app pushes. On a wide window the
/// page sits in a centred panel instead of stretching edge to edge.
Route<T> appRoute<T>(Widget page) => MaterialPageRoute<T>(builder: (_) => _Framed(child: page));

class _Framed extends StatelessWidget {
  const _Framed({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < Bp.wide) return child;
        return ColoredBox(
          color: C.sunken,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SizedBox.expand(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: C.bg,
                    border: Border.symmetric(vertical: BorderSide(color: C.sunken)),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      });
}
