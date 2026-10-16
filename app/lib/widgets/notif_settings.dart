import 'dart:io';
import 'package:flutter/material.dart';
import '../services/alerts.dart';
import '../services/bubble.dart';
import '../theme.dart';
import 'clay.dart';

/// Settings rows for the floating bubble and background alerts (Android only).
class NotifSettings extends StatefulWidget {
  const NotifSettings({super.key});
  @override
  State<NotifSettings> createState() => _NotifSettingsState();
}

class _NotifSettingsState extends State<NotifSettings> with WidgetsBindingObserver {
  bool _bubble = false;
  bool _listener = true;
  bool _loaded = false;
  bool _waitingForPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final b = await Bubble.isEnabled();
    final l = await Bubble.listenerEnabled();
    if (!mounted) return;
    setState(() {
      _bubble = b;
      _listener = l;
      _loaded = true;
    });
  }

  // back from the system "display over other apps" screen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForPermission) {
      _waitingForPermission = false;
      Bubble.canDraw().then((ok) {
        if (ok) _toggleBubble(true);
      });
    }
  }

  Future<void> _toggleBubble(bool on) async {
    final done = await Bubble.setEnabled(on);
    if (!mounted) return;
    if (on && !done) {
      _waitingForPermission = true;
      toast(context, 'Allow "Display over other apps" for HelpHive, then come back.');
    }
    setState(() => _bubble = on && done);
  }

  Future<void> _toggleListener(bool on) async {
    await Bubble.setListenerEnabled(on);
    if (on) {
      await Alerts.I.startListener();
    } else {
      await Alerts.I.stopListener(hideBubble: false);
    }
    if (mounted) setState(() => _listener = on);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid || !_loaded) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _Row(
        icon: 'chat_fill',
        title: 'Floating chat bubble',
        subtitle: 'Shows over every app. Drag it to the X at the bottom to remove it.',
        value: _bubble,
        onChanged: _toggleBubble,
      ),
      const SizedBox(height: 10),
      _Row(
        icon: 'bell_fill',
        title: 'Alerts when the app is closed',
        subtitle: 'Keeps listening quietly so messages and alerts reach your notification drawer.',
        value: _listener,
        onChanged: _toggleListener,
      ),
      const SizedBox(height: 10),
      ClayButton(label: 'Keep alerts running (battery)', icon: 'check_circle', tone: ClayTone.soft, onPressed: Bubble.requestBatteryExemption),
      const SizedBox(height: 14),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => ClayCard(
        radius: 22,
        depth: .4,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          HIcon(icon, size: 22, color: C.honeyDeep),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: C.inkSoft, fontSize: 12.5, height: 1.3)),
            ]),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: C.honeyDeep),
        ]),
      );
}
