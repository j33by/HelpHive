import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color, DartPluginRegistrant;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_state.dart';
import '../config.dart';
import '../layout.dart';
import '../models.dart';
import '../screens/chat.dart';
import 'api.dart';
import 'secure_store.dart';

/// Lets alerts open screens from outside the widget tree (notification taps).
final navigatorKey = GlobalKey<NavigatorState>();

/// A message or alert that just arrived, shown as a preview next to the bubble.
class Incoming {
  Incoming({required this.isMessage, required this.user, required this.text, this.conversationId});
  final bool isMessage;
  final UserLite user;
  final String text;
  final String? conversationId;
}

/// "Name did something" wording shared by the system notification, the bubble
/// panel and the Alerts tab.
(String, String?) notifSummary(Notif n) {
  final q = n.snippet == null ? null : '“${n.snippet}”';
  switch (n.type) {
    case 'friend_request':
      return ('sent you a friend request', null);
    case 'friend_accepted':
      return ('accepted your friend request', null);
    case 'post_reaction':
      return ('reacted to your post', null);
    case 'post_comment':
      return ('commented on your post', q);
    case 'comment_reply':
      return ('replied to your comment', q);
    case 'comment_reaction':
      return ('reacted to your comment', null);
    default:
      return ('did something', null);
  }
}

/// Icon (from assets/icons) that stands for each alert type.
String notifIcon(Notif n) {
  switch (n.type) {
    case 'friend_request':
      return 'user_add';
    case 'friend_accepted':
      return 'user_check';
    case 'post_comment':
    case 'comment_reply':
      return 'comment_fill';
    default:
      return 'heart_fill';
  }
}

int _stableId(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

Future<void> _ensureBackend() async {
  try {
    Supabase.instance.client;
    return;
  } catch (_) {}
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce, localStorage: SecureSessionStorage()),
  );
}

/// Like / Reply pressed on a notification in the phone's drawer. This can run
/// while the app is closed, so it brings up its own backend connection.
Future<void> _runAction(NotificationResponse r) async {
  try {
    final data = jsonDecode(r.payload ?? '{}') as Map<String, dynamic>;
    if (data['k'] != 'msg') return;
    final conv = data['c'] as String;
    await _ensureBackend();
    if (r.actionId == 'like') {
      final m = data['m'] as String?;
      if (m != null && m.isNotEmpty) await Api.reactMessage(m, 'like');
    } else if (r.actionId == 'reply') {
      final t = (r.input ?? '').trim();
      if (t.isEmpty) return;
      await Api.sendMessage(conv, t);
    }
    await Api.markRead(conv);
  } catch (_) {}
}

@pragma('vm:entry-point')
void notificationBackground(NotificationResponse r) {
  _runAction(r);
}

class Alerts extends ChangeNotifier {
  Alerts._();
  static final Alerts I = Alerts._();

  static const _chMessages = 'hh_messages_v1';
  static const _chAlerts = 'hh_alerts_v1';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _msgPlayer = AudioPlayer();
  final _alertPlayer = AudioPlayer();

  List<Conversation> conversations = [];
  List<Notif> notifs = [];
  final latest = ValueNotifier<Incoming?>(null);

  /// Bumped to make the bubble panel close (e.g. when a screen opens).
  final closePanel = ValueNotifier<int>(0);
  final Set<String> liked = {};

  /// Set by the open chat screen so its own messages don't pop up.
  String? activeConversation;

  bool _ready = false;
  bool _primed = false;
  bool _busy = false;
  final Map<String, int> _seenConv = {};
  final Set<String> _seenNotif = {};
  Set<String> _unreadConvs = {};
  NotificationResponse? _launch;
  Timer? _clearLatest;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    if (!Platform.isAndroid) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('ic_stat_chat')),
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse: notificationBackground,
      );
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) _launch = d!.notificationResponse;
    } catch (_) {}
  }

  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Called once the main screen is up, to open whatever a tap on a
  /// notification started the app for.
  void consumeLaunch() {
    final r = _launch;
    _launch = null;
    if (r != null) _onResponse(r);
  }

  void reset() {
    _primed = false;
    _seenConv.clear();
    _seenNotif.clear();
    _unreadConvs = {};
    conversations = [];
    notifs = [];
    liked.clear();
    latest.value = null;
    if (Platform.isAndroid) _plugin.cancelAll().catchError((_) {});
    notifyListeners();
  }

  // ---- sounds
  Future<void> _play(AudioPlayer p, String asset) async {
    try {
      await p.stop();
      await p.play(AssetSource(asset));
    } catch (_) {}
  }

  // ---- polling diff
  Future<void> check() async {
    if (_busy) return;
    _busy = true;
    try {
      final convs = await Api.conversations();
      final ns = (await Api.notifications()).items;
      final tab = AppState.I.tab.value;

      final newMsgs = <Conversation>[];
      final newNotifs = <Notif>[];
      if (_primed) {
        for (final c in convs) {
          final seen = _seenConv[c.id];
          final fresh = c.unread > 0 && !c.lastMine && !c.lastDeleted && (seen == null || c.lastAt.millisecondsSinceEpoch > seen);
          if (fresh && c.id != activeConversation) newMsgs.add(c);
        }
        for (final n in ns) {
          if (!n.read && !_seenNotif.contains(n.id) && n.actor.id.isNotEmpty && tab != 2) newNotifs.add(n);
        }
      }

      // anything read elsewhere should leave the drawer too
      if (Platform.isAndroid) {
        for (final c in convs) {
          if (c.unread == 0 && _unreadConvs.contains(c.id)) _plugin.cancel(_stableId(c.id)).catchError((_) {});
        }
        for (final n in ns) {
          if (n.read) _plugin.cancel(_stableId(n.id)).catchError((_) {});
        }
      }

      for (final c in convs) {
        _seenConv[c.id] = c.lastAt.millisecondsSinceEpoch;
      }
      for (final n in ns) {
        _seenNotif.add(n.id);
      }
      _unreadConvs = {for (final c in convs) if (c.unread > 0) c.id};
      conversations = convs;
      notifs = ns;
      _primed = true;
      notifyListeners();

      if (newMsgs.isNotEmpty) {
        _play(_msgPlayer, 'sounds/message.wav');
        final c = newMsgs.first;
        _announce(Incoming(isMessage: true, user: c.user, text: c.lastBody, conversationId: c.id));
        for (final c in newMsgs) {
          _postMessage(c);
        }
      }
      if (newNotifs.isNotEmpty) {
        _play(_alertPlayer, 'sounds/alert.wav');
        if (newMsgs.isEmpty) {
          final n = newNotifs.first;
          final (what, quote) = notifSummary(n);
          _announce(Incoming(isMessage: false, user: n.actor, text: quote == null ? what : '$what: $quote'));
        }
        for (final n in newNotifs) {
          _postAlert(n);
        }
      }
    } catch (_) {
      // transient; the next badge change tries again
    } finally {
      _busy = false;
    }
  }

  void _announce(Incoming i) {
    latest.value = i;
    _clearLatest?.cancel();
    _clearLatest = Timer(const Duration(seconds: 6), () => latest.value = null);
  }

  void dismissLatest() {
    _clearLatest?.cancel();
    latest.value = null;
  }

  // ---- quick actions (bubble panel)
  Future<void> likeLast(Conversation c) async {
    if (c.lastId.isEmpty || liked.contains(c.id)) return;
    liked.add(c.id);
    notifyListeners();
    try {
      await Api.reactMessage(c.lastId, 'like');
    } catch (e) {
      liked.remove(c.id);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reply(Conversation c, String text) async {
    await Api.sendMessage(c.id, text);
    await Api.markRead(c.id);
    if (Platform.isAndroid) _plugin.cancel(_stableId(c.id)).catchError((_) {});
    await AppState.I.refreshBadges();
    await check();
  }

  Future<void> markAlertRead(Notif n) async {
    if (n.read) return;
    n.read = true;
    notifyListeners();
    Api.readNotification(n.id).then((_) => AppState.I.refreshBadges()).catchError((_) {});
  }

  void openChat(String conversationId, UserLite user) {
    closePanel.value++;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    AppState.I.tab.value = 3;
    nav.push(appRoute(ChatScreen(conversationId: conversationId, other: user)));
  }

  // ---- system notifications (the phone's drawer)
  Future<AndroidBitmap<Object>> _large(String? url) async {
    if (url != null && url.startsWith('http')) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return ByteArrayAndroidBitmap(r.bodyBytes);
      } catch (_) {}
    }
    return const DrawableResourceAndroidBitmap('ic_large_bee');
  }

  Future<void> _postMessage(Conversation c) async {
    if (!Platform.isAndroid) return;
    try {
      final payload = jsonEncode({
        'k': 'msg',
        'c': c.id,
        'm': c.lastId,
        'u': {'id': c.user.id, 'username': c.user.username, 'fullName': c.user.fullName, 'avatarUrl': c.user.avatarUrl},
      });
      await _plugin.show(
        _stableId(c.id),
        c.user.display,
        c.lastBody,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chMessages,
            'Messages',
            channelDescription: 'New chat messages',
            importance: Importance.high,
            priority: Priority.high,
            playSound: false, // the app plays its own tone
            icon: 'ic_stat_chat',
            largeIcon: await _large(c.user.avatarUrl),
            color: const Color(0xFFF2B33D),
            category: AndroidNotificationCategory.message,
            styleInformation: BigTextStyleInformation(c.lastBody, contentTitle: c.user.display, summaryText: 'HelpHive message'),
            actions: <AndroidNotificationAction>[
              const AndroidNotificationAction('like', 'Like', icon: DrawableResourceAndroidBitmap('ic_action_like'), cancelNotification: true),
              AndroidNotificationAction(
                'reply',
                'Reply',
                icon: const DrawableResourceAndroidBitmap('ic_action_reply'),
                cancelNotification: true,
                allowGeneratedReplies: true,
                inputs: <AndroidNotificationActionInput>[AndroidNotificationActionInput(label: 'Reply to ${c.user.display}')],
              ),
            ],
          ),
        ),
        payload: payload,
      );
    } catch (_) {}
  }

  Future<void> _postAlert(Notif n) async {
    if (!Platform.isAndroid) return;
    try {
      final (what, quote) = notifSummary(n);
      final body = quote == null ? what : '$what\n$quote';
      await _plugin.show(
        _stableId(n.id),
        n.actor.display,
        quote == null ? what : '$what: $quote',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chAlerts,
            'Alerts',
            channelDescription: 'Friend requests, reactions and comments',
            importance: Importance.high,
            priority: Priority.high,
            playSound: false,
            icon: 'ic_stat_bell',
            largeIcon: await _large(n.actor.avatarUrl),
            color: const Color(0xFFF2B33D),
            category: AndroidNotificationCategory.social,
            styleInformation: BigTextStyleInformation(body, contentTitle: n.actor.display, summaryText: 'HelpHive alert'),
          ),
        ),
        payload: jsonEncode({'k': 'alert', 'id': n.id, 'p': n.postId, 'u': n.actor.id, 't': n.type}),
      );
    } catch (_) {}
  }

  // ---- taps
  void _onResponse(NotificationResponse r) {
    if (r.actionId == 'like' || r.actionId == 'reply') {
      _runAction(r).then((_) => AppState.I.refreshBadges());
      return;
    }
    try {
      final d = jsonDecode(r.payload ?? '{}') as Map<String, dynamic>;
      if (d['k'] == 'msg') {
        final u = d['u'] as Map<String, dynamic>;
        openChat(d['c'] as String, UserLite.fromJson(u));
      } else if (d['k'] == 'alert') {
        AppState.I.tab.value = 2;
      }
    } catch (_) {}
  }
}
