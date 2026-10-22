import 'package:flutter/material.dart';

/// One rung of the helper ladder. A person wears the highest tier their star
/// total reaches. Thresholds are mirrored in server/src/stars.js (keep in step).
class BadgeTier {
  const BadgeTier({
    required this.key,
    required this.name,
    required this.min,
    required this.quote,
    required this.light,
    required this.dark,
    required this.glow,
  });
  final String key;
  final String name;

  /// Stars needed to earn it.
  final int min;
  final String quote;

  /// Metal / gem colours: highlight, shade, and the colour of the shine around it.
  final Color light;
  final Color dark;
  final Color glow;
}

const badgeTiers = <BadgeTier>[
  BadgeTier(
    key: 'fresh_buzz',
    name: 'Fresh Buzz',
    min: 1,
    quote: 'Every hive starts with a single buzz.',
    light: Color(0xFFF0B98A),
    dark: Color(0xFFB36A33),
    glow: Color(0xFFE59A5B),
  ),
  BadgeTier(
    key: 'helping_wing',
    name: 'Helping Wing',
    min: 3,
    quote: 'Small help, big difference.',
    light: Color(0xFFF3F5F8),
    dark: Color(0xFF8E9AA8),
    glow: Color(0xFFBFD0E4),
  ),
  BadgeTier(
    key: 'worker_bee',
    name: 'Worker Bee',
    min: 5,
    quote: 'Busy wings keep the hive humming.',
    light: Color(0xFFFFE27A),
    dark: Color(0xFFE3A112),
    glow: Color(0xFFFFC83D),
  ),
  BadgeTier(
    key: 'honey_maker',
    name: 'Honey Maker',
    min: 10,
    quote: 'Kindness tastes sweetest when shared.',
    light: Color(0xFFFFC46B),
    dark: Color(0xFFD9650F),
    glow: Color(0xFFFF9A3C),
  ),
  BadgeTier(
    key: 'hive_guardian',
    name: 'Hive Guardian',
    min: 25,
    quote: 'Strong hives are built by steady hands.',
    light: Color(0xFF86E8B2),
    dark: Color(0xFF1B9560),
    glow: Color(0xFF3FD28C),
  ),
  BadgeTier(
    key: 'nectar_hero',
    name: 'Nectar Hero',
    min: 50,
    quote: 'Your help is worth its weight in honey.',
    light: Color(0xFF9CCDFF),
    dark: Color(0xFF2860CC),
    glow: Color(0xFF5B9BFF),
  ),
  BadgeTier(
    key: 'queen_bee',
    name: 'Queen Bee',
    min: 100,
    quote: 'The whole hive thrives because of you.',
    light: Color(0xFFE2B8FF),
    dark: Color(0xFF7430C4),
    glow: Color(0xFFB56BFF),
  ),
];

/// The badge a person with [stars] wears, or null before their first star.
BadgeTier? badgeForStars(int stars) {
  BadgeTier? best;
  for (final t in badgeTiers) {
    if (stars >= t.min) best = t;
  }
  return best;
}

/// The next badge to aim for, or null at the top.
BadgeTier? nextBadge(int stars) {
  for (final t in badgeTiers) {
    if (stars < t.min) return t;
  }
  return null;
}
