import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'clay.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _eventWhen(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${_days[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day} · $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// An update, event or alert from the HelpHive team, shown at the top of the feed.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({super.key, required this.item});
  final Announcement item;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (item.kind) {
      'event' => ('EVENT', Icons.event),
      'alert' => ('IMPORTANT', Icons.campaign_outlined),
      _ => ('UPDATE', Icons.auto_awesome_outlined),
    };
    return ClayCard(
      color: item.kind == 'alert' ? C.honeyPale : C.surface,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: C.honeyDeep),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: C.honeyDeep)),
          const SizedBox(width: 8),
          const Expanded(child: Text('HelpHive Team', style: TextStyle(fontSize: 12, color: C.inkSoft, fontWeight: FontWeight.w600))),
          if (item.pinned) const Icon(Icons.push_pin_outlined, size: 16, color: C.inkSoft),
        ]),
        const SizedBox(height: 8),
        Text(item.title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.25)),
        if (item.kind == 'event' && item.eventAt != null) ...[
          const SizedBox(height: 4),
          Text('${_eventWhen(item.eventAt!)}${(item.location ?? '').isNotEmpty ? ' · ${item.location}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
        ],
        if (item.body.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(item.body, style: const TextStyle(height: 1.4, color: C.ink)),
        ],
      ]),
    );
  }
}
