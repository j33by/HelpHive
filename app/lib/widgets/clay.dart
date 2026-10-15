import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Soft raised shape: a light shadow top-left, a warm dark one bottom-right.
BoxDecoration clayDeco({Color color = C.surface, double radius = 24, double depth = 1}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(color: C.shadowDark.withValues(alpha: .85), offset: Offset(6 * depth, 7 * depth), blurRadius: 16 * depth),
        BoxShadow(color: Colors.white.withValues(alpha: .95), offset: Offset(-5 * depth, -5 * depth), blurRadius: 12 * depth),
      ],
    );

/// Pressed-in shape for inputs.
BoxDecoration sunkenDeco({double radius = 20}) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE6DAC8), Color(0xFFF2EADD)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .7), width: 1.2),
    );

class HIcon extends StatelessWidget {
  const HIcon(this.name, {super.key, this.size = 24, this.color = C.ink});
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/icons/$name.png',
        width: size,
        height: size,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
      );
}

class Press extends StatefulWidget {
  const Press({super.key, required this.child, this.onTap, this.onLongPress, this.scale = .97});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final live = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: live ? (_) => setState(() => _down = true) : null,
      onTapCancel: live ? () => setState(() => _down = false) : null,
      onTapUp: live ? (_) => setState(() => _down = false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}

class ClayCard extends StatelessWidget {
  const ClayCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24, this.color = C.surface, this.onTap, this.depth = 1});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final VoidCallback? onTap;
  final double depth;
  @override
  Widget build(BuildContext context) {
    final box = Container(decoration: clayDeco(color: color, radius: radius, depth: depth), padding: padding, child: child);
    return onTap == null ? box : Press(onTap: onTap, scale: .985, child: box);
  }
}

class ClayButton extends StatelessWidget {
  const ClayButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.small = false,
    this.tone = ClayTone.honey,
  });
  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final bool loading;
  final bool expanded;
  final bool small;
  final ClayTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = switch (tone) { ClayTone.honey => C.honey, ClayTone.soft => C.surface, ClayTone.danger => C.rose };
    final fg = switch (tone) { ClayTone.honey => C.ink, ClayTone.soft => C.ink, ClayTone.danger => Colors.white };
    final enabled = onPressed != null && !loading;
    final h = small ? 38.0 : 54.0;
    final content = loading
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[HIcon(icon!, size: small ? 16 : 20, color: fg), SizedBox(width: small ? 6 : 8)],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: small ? 13 : 16, color: fg)),
              ),
            ],
          );
    return Opacity(
      opacity: enabled || loading ? 1 : .5,
      child: Press(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: h,
          width: expanded ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: small ? 14 : 22),
          alignment: Alignment.center,
          decoration: clayDeco(color: bg, radius: h / 2, depth: small ? .6 : .85),
          child: content,
        ),
      ),
    );
  }
}

enum ClayTone { honey, soft, danger }

class ClayIconButton extends StatelessWidget {
  const ClayIconButton({super.key, required this.icon, this.onTap, this.size = 44, this.color = C.ink, this.bg = C.surface, this.badge = 0});
  final String icon;
  final VoidCallback? onTap;
  final double size;
  final Color color;
  final Color bg;
  final int badge;
  @override
  Widget build(BuildContext context) {
    return Press(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: clayDeco(color: bg, radius: size / 2, depth: .55),
          child: HIcon(icon, size: size * .48, color: color),
        ),
        if (badge > 0) Positioned(right: -2, top: -2, child: CountDot(badge)),
      ]),
    );
  }
}

class CountDot extends StatelessWidget {
  const CountDot(this.n, {super.key});
  final int n;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 18),
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: C.rose, borderRadius: BorderRadius.circular(9), border: Border.all(color: C.bg, width: 1.5)),
        child: Text(n > 99 ? '99+' : '$n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.url, required this.name, this.size = 44});
  final String? url;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      color: C.honeyPale,
      alignment: Alignment.center,
      child: Text(initial, style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * .42, color: C.honeyDeep)),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .05),
      decoration: clayDeco(color: C.surface, radius: size, depth: size < 50 ? .4 : .7),
      child: ClipOval(
        child: url == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

class ClayField extends StatelessWidget {
  const ClayField({
    super.key,
    this.controller,
    this.hint,
    this.icon,
    this.obscure = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.validator,
    this.textInputAction,
    this.autofocus = false,
    this.suffix,
    this.focusNode,
    this.autofillHints,
  });
  final TextEditingController? controller;
  final String? hint;
  final String? icon;
  final bool obscure;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final Widget? suffix;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: sunkenDeco(),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: maxLines == 1 ? 2 : 6),
      child: Row(
        crossAxisAlignment: maxLines == 1 ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Padding(
              padding: EdgeInsets.only(right: 12, top: maxLines == 1 ? 0 : 12),
              child: HIcon(icon!, size: 20, color: C.inkSoft),
            ),
          Expanded(
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscure,
              maxLines: maxLines,
              minLines: minLines,
              maxLength: maxLength,
              onChanged: onChanged,
              onFieldSubmitted: onSubmitted,
              keyboardType: keyboardType,
              validator: validator,
              autofocus: autofocus,
              autofillHints: autofillHints,
              textInputAction: textInputAction,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
              cursorColor: C.honeyDeep,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: C.inkSoft, fontWeight: FontWeight.w500),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                counterText: '',
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                errorStyle: const TextStyle(color: C.rose, fontWeight: FontWeight.w600, height: 1.1),
              ),
            ),
          ),
          if (suffix != null) suffix!,
        ],
      ),
    );
  }
}

class Chip2 extends StatelessWidget {
  const Chip2({super.key, required this.label, required this.selected, required this.onTap, this.count = 0});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int count;
  @override
  Widget build(BuildContext context) {
    return Press(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: selected
            ? clayDeco(color: C.honey, radius: 20, depth: .45)
            : clayDeco(color: C.surface, radius: 20, depth: .35),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: selected ? C.ink : C.inkSoft)),
          if (count > 0) ...[const SizedBox(width: 6), CountDot(count)],
        ]),
      ),
    );
  }
}

class Empty extends StatelessWidget {
  const Empty({super.key, required this.title, this.subtitle, this.icon = 'hex_cell'});
  final String title;
  final String? subtitle;
  final String icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: clayDeco(color: C.honeyPale, radius: 42, depth: .7),
              child: HIcon(icon, size: 36, color: C.honeyDeep),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: C.inkSoft, height: 1.35)),
            ],
          ]),
        ),
      );
}

class Failed extends StatelessWidget {
  const Failed({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Hmm, that did not load', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: C.inkSoft)),
            const SizedBox(height: 18),
            ClayButton(label: 'Try again', onPressed: onRetry, expanded: false, small: true),
          ]),
        ),
      );
}

Future<bool> confirm(BuildContext context, {required String title, required String body, String yes = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: C.inkSoft))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes, style: TextStyle(color: danger ? C.rose : C.honeyDeep, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}
