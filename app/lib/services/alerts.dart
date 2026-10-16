import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color, DartPluginRegistrant;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_state.dart';
import '../config.dart';
import '../layout.dart';
import '../models.dart';
import '../screens/chat.dart';
import 'api.dart';
import 'bubble.dart';
import 'secure_store.dart';

/// Lets alerts open screens from outside the widget tree (notification taps).
final navigatorKey = GlobalKey<NavigatorState>();

/// "Name did something" wording shared by the system notification and the Alerts tab.
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

int _stableId(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

Map<String, dynamic> _userJson(UserLite u) => {'id': u.id, 'username': u.username, 'fullName': u.fullName, 'avatarUrl': u.avatarUrl};

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
    // The app owns token refreshing; background isolates only borrow its session
    // (see _syncSession) so two refreshers never fight over one refresh token.
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce, localStorage: SecureSessionStorage(), autoRefreshToken: false),
  );
}

/// Loads the newest saved session into this isolate. Returns false when signed out.
Future<bool> _syncSession() async {
  try {
    final raw = await const SecureSessionStorage().accessToken();
    if (raw == null || raw.isEmpty) return false;
    final auth = Supabase.instance.client.auth;
    final cur = auth.currentSession;
    final rt = (jsonDecode(raw) as Map)['refresh_token'];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (cur == null || cur.refreshToken != rt || (cur.expiresAt ?? 0) - now < 60) {
      await auth.recoverSession(raw);
    }
    return auth.currentSession != null;
  } catch (_) {
    return false;
  }
}

/// Like / Reply pressed on a notification in the phone's drawer. This can run
/// while the app is closed, so it brings up its own backend connection.
Future<void> _runAction(NotificationResponse r) async {
  try {
    final data = jsonDecode(r.payload ?? '{}') as Map<String, dynamic>;
    if (data['k'] != 'msg') return;
    final conv = data['c'] as String;
    await _ensureBackend();
    if (!await _syncSession()) return;
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

// ============================================================================
// Background listener. Runs in its own isolate inside an Android foreground
// service, so it keeps listening while the app is in the background or has
// been swiped away. It posts the phone notifications (with the two tones),
// feeds the floating bubble and tells the app, if it is open, to play a tone.
// ============================================================================

const _listenerChannel = 'hh_listener';

@pragma('vm:entry-point')
Future<void> listenerMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  final l = _Listener(service);
  service.on('stop').listen((_) => service.stopSelf());
  service.on('ui').listen((e) => l.ui(e ?? const {}));
  try {
    await _ensureBackend();
    await l.init();
  } catch (_) {}
  Timer.periodic(const Duration(seconds: 8), (_) => l.tick());
  l.tick();
}

class _Listener {
  _Listener(this.service);
  final ServiceInstance service;
  final _plugin = FlutterLocalNotificationsPlugin();

  bool _primed = false;
  bool _busy = false;
  int _n = -1, _m = -1;
  final Map<String, int> _seenConv = {};
  final Set<String> _seenNotif = {};
  Set<String> _unreadConvs = {};

  // what the app told us about itself
  bool _fg = false;
  DateTime _beat = DateTime.fromMillisecondsSinceEpoch(0);
  String? _activeConv;
  int _tab = 0;

  bool get _appOpen => _fg && DateTime.now().difference(_beat) < const Duration(seconds: 14);

  void ui(Map<String, dynamic> e) {
    _fg = e['fg'] == true;
    _beat = DateTime.now();
    _activeConv = e['conv'] as String?;
    _tab = (e['tab'] as num?)?.toInt() ?? 0;
  }

  Future<void> init() async {
    if (!Platform.isAndroid) return;
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('ic_stat_chat')));
  }

  Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await _syncSession()) return;
      final b = await Api.badges();
      if (_primed && b.notifications == _n && b.messages == _m) return;
      final convs = await Api.conversations();
      final ns = (await Api.notifications()).items;

      final newMsgs = <Conversation>[];
      final newNotifs = <Notif>[];
      if (_primed) {
        for (final c in convs) {
          final seen = _seenConv[c.id];
          final fresh = c.unread > 0 && !c.lastMine && !c.lastDeleted && (seen == null || c.lastAt.millisecondsSinceEpoch > seen);
          if (fresh && !(_appOpen && c.id == _activeConv)) newMsgs.add(c);
        }
        for (final n in ns) {
          if (!n.read && !_seenNotif.contains(n.id) && n.actor.id.isNotEmpty && !(_appOpen && _tab == 2)) newNotifs.add(n);
        }
      }

      // read elsewhere, so it should leave the drawer too
      for (final c in convs) {
        if (c.unread == 0 && _unreadConvs.contains(c.id)) _plugin.cancel(_stableId(c.id)).catchError((_) {});
      }
      for (final n in ns) {
        if (n.read) _plugin.cancel(_stableId(n.id)).catchError((_) {});
      }

      for (final c in convs) {
        _seenConv[c.id] = c.lastAt.millisecondsSinceEpoch;
      }
      for (final n in ns) {
        _seenNotif.add(n.id);
      }
      _unreadConvs = {for (final c in convs) if (c.unread > 0) c.id};
      _n = b.notifications;
      _m = b.messages;
      final first = !_primed;
      _primed = true;

      // ---- bubble
      final unreadConv = convs.where((c) => c.unread > 0).firstOrNull;
      Map<String, dynamic>? preview;
      String latest = '';
      if (unreadConv != null) {
        latest = jsonEncode({'k': 'msg', 'c': unreadConv.id, 'u': _userJson(unreadConv.user)});
      } else if (b.notifications > 0) {
        latest = jsonEncode({'k': 'alert'});
      }
      if (newMsgs.isNotEmpty) {
        final c = newMsgs.first;
        preview = {'title': c.user.display, 'text': c.lastBody, 'avatar': c.user.avatarUrl, 'tick': DateTime.now().millisecondsSinceEpoch};
        latest = jsonEncode({'k': 'msg', 'c': c.id, 'u': _userJson(c.user)});
      } else if (newNotifs.isNotEmpty) {
        final n = newNotifs.first;
        final (what, quote) = notifSummary(n);
        preview = {'title': n.actor.display, 'text': quote == null ? what : '$what: $quote', 'avatar': n.actor.avatarUrl, 'tick': DateTime.now().millisecondsSinceEpoch};
      }
      await Bubble.publish(
        unread: b.messages + b.notifications,
        head: unreadConv == null ? {} : {'name': unreadConv.user.display, 'avatar': unreadConv.user.avatarUrl},
        preview: preview,
        latest: latest,
      );

      // ---- phone drawer + tones
      if (!first) {
        if (newMsgs.isNotEmpty) service.invoke('incoming', {'kind': 'msg'});
        if (newNotifs.isNotEmpty) service.invoke('incoming', {'kind': 'alert'});
        for (final c in newMsgs) {
          await _postMessage(c);
        }
        for (final n in newNotifs) {
          await _postAlert(n);
        }
      }
    } catch (_) {
      // transient; the next tick tries again
    } finally {
      _busy = false;
    }
  }

  Future<AndroidBitmap<Object>> _large(String? url) async {
    if (url != null && url.startsWith('http')) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return ByteArrayAndroidBitmap(r.bodyBytes);
      } catch (_) {}
    }
    return const DrawableResourceAndroidBitmap('ic_large_bee');
  }

  // With the app open the app plays the tone itself, so the notification is
  // posted on a silent channel. Otherwise the channel carries the tone, which
  // also works while the app is closed.
  AndroidNotificationDetails _details({
    required bool message,
    required String title,
    required String body,
    required AndroidBitmap<Object> large,
    List<AndroidNotificationAction>? actions,
  }) {
    final quiet = _appOpen;
    final id = message ? (quiet ? 'hh_msg_quiet_v2' : 'hh_msg_tone_v2') : (quiet ? 'hh_alert_quiet_v2' : 'hh_alert_tone_v2');
    final name = message ? (quiet ? 'Messages (app open)' : 'Messages') : (quiet ? 'Alerts (app open)' : 'Alerts');
    return AndroidNotificationDetails(
      id,
      name,
      channelDescription: message ? 'New chat messages' : 'Friend requests, reactions and comments',
      importance: Importance.high,
      priority: Priority.high,
      playSound: !quiet,
      sound: quiet ? null : RawResourceAndroidNotificationSound(message ? 'message_tone' : 'alert_tone'),
      enableVibration: !quiet,
      icon: message ? 'ic_stat_chat' : 'ic_stat_bell',
      largeIcon: large,
      color: const Color(0xFFF2B33D),
      category: message ? AndroidNotificationCategory.message : AndroidNotificationCategory.social,
      styleInformation: BigTextStyleInformation(body, contentTitle: title, summaryText: message ? 'HelpHive message' : 'HelpHive alert'),
      actions: actions,
    );
  }

  Future<void> _postMessage(Conversation c) async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.show(
        _stableId(c.id),
        c.user.display,
        c.lastBody,
        NotificationDetails(
          android: _details(
            message: true,
            title: c.user.display,
            body: c.lastBody,
            large: await _large(c.user.avatarUrl),
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
        payload: jsonEncode({'k': 'msg', 'c': c.id, 'm': c.lastId, 'u': _userJson(c.user)}),
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
        NotificationDetails(android: _details(message: false, title: n.actor.display, body: body, large: await _large(n.actor.avatarUrl))),
        payload: jsonEncode({'k': 'alert', 'id': n.id, 'p': n.postId, 'u': n.actor.id, 't': n.type}),
      );
    } catch (_) {}
  }
}

// ============================================================================
// The app side: starts the listener, plays the in-app tones, handles taps.
// ============================================================================

class Alerts with WidgetsBindingObserver {
  Alerts._();
  static final Alerts I = Alerts._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _msgPlayer = AudioPlayer();
  final _alertPlayer = AudioPlayer();

  bool _ready = false;
  bool _fg = true;
  Timer? _beat;
  NotificationResponse? _launch;
  String? _activeConversation;

  /// Set by the open chat screen so its own messages don't announce themselves.
  String? get activeConversation => _activeConversation;
  set activeConversation(String? v) {
    _activeConversation = v;
    _pushUi();
  }

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    AppState.I.tab.addListener(_pushUi);
    try {
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('ic_stat_chat')),
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse: notificationBackground,
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      // the foreground service needs its channel before it starts
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _listenerChannel,
        'Background listener',
        description: 'Keeps HelpHive listening for new messages and alerts',
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ));
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) _launch = d!.notificationResponse;

      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: listenerMain,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          notificationChannelId: _listenerChannel,
          initialNotificationTitle: 'HelpHive',
          initialNotificationContent: 'Listening for new messages and alerts',
          foregroundServiceNotificationId: 8800,
          foregroundServiceTypes: [AndroidForegroundType.specialUse],
        ),
        iosConfiguration: IosConfiguration(),
      );
      FlutterBackgroundService().on('incoming').listen((e) {
        if (_fg) _play(e?['kind'] == 'alert');
      });
    } catch (_) {}
  }

  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Begin listening (after sign-in and on every launch while signed in).
  Future<void> startListener() async {
    if (!Platform.isAndroid) return;
    await requestPermission();
    Bubble.resume();
    if (!await Bubble.listenerEnabled()) return;
    try {
      final s = FlutterBackgroundService();
      if (!await s.isRunning()) await s.startService();
      _startBeat();
      _pushUi();
    } catch (_) {}
  }

  /// Stop listening (sign-out, or the switch in settings).
  Future<void> stopListener({bool hideBubble = true}) async {
    if (!Platform.isAndroid) return;
    _beat?.cancel();
    try {
      FlutterBackgroundService().invoke('stop');
    } catch (_) {}
    if (hideBubble) Bubble.hide();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  void _startBeat() {
    _beat?.cancel();
    _beat = Timer.periodic(const Duration(seconds: 5), (_) => _pushUi());
  }

  void _pushUi() {
    if (!Platform.isAndroid) return;
    try {
      FlutterBackgroundService().invoke('ui', {'fg': _fg, 'conv': _activeConversation, 'tab': AppState.I.tab.value});
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _fg = state == AppLifecycleState.resumed;
    _pushUi();
    if (_fg) {
      _adoptSavedSession();
      takeBubbleLaunch();
    }
  }

  // The listener may have refreshed the token while the app slept; take the newer one
  // so this isolate never refreshes with a refresh token that was already used.
  Future<void> _adoptSavedSession() async {
    try {
      final raw = await const SecureSessionStorage().accessToken();
      final auth = Supabase.instance.client.auth;
      final cur = auth.currentSession;
      if (raw == null || cur == null) return;
      if ((jsonDecode(raw) as Map)['refresh_token'] != cur.refreshToken) await auth.recoverSession(raw);
    } catch (_) {}
  }

  DateTime _lastTone = DateTime.fromMillisecondsSinceEpoch(0);

  /// Called by AppState when the unread counts grow while the app is open, so the
  /// tone plays even if the background listener has not reported yet.
  void onBadgeGrowth({required bool messages, required bool alerts}) {
    if (!_fg) return;
    if (messages && _activeConversation == null) {
      _play(false);
    } else if (alerts && AppState.I.tab.value != 2) {
      _play(true);
    }
  }

  Future<void> _play(bool alert) async {
    // the listener and the badge poll can both report the same event
    final now = DateTime.now();
    if (now.difference(_lastTone) < const Duration(seconds: 3)) return;
    _lastTone = now;
    final p = alert ? _alertPlayer : _msgPlayer;
    try {
      await p.stop();
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setVolume(1.0);
      await p.play(AssetSource(alert ? 'sounds/alert.wav' : 'sounds/message.wav'));
    } catch (_) {}
  }

  // ---- opening things
  void openChat(String conversationId, UserLite user) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    AppState.I.tab.value = 3;
    nav.push(appRoute(ChatScreen(conversationId: conversationId, other: user)));
  }

  void _openPayload(String? raw) {
    if (raw == null || raw.isEmpty) {
      AppState.I.tab.value = 3;
      return;
    }
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      if (d['k'] == 'msg') {
        openChat(d['c'] as String, UserLite.fromJson(d['u'] as Map<String, dynamic>));
      } else if (d['k'] == 'alert') {
        AppState.I.tab.value = 2;
      }
    } catch (_) {}
  }

  /// A tap on the floating bubble starts or resumes the app with a payload.
  Future<void> takeBubbleLaunch() async {
    final raw = await Bubble.takeLaunch();
    if (raw != null) _openPayload(raw);
  }

  /// Called once the main screen is up, for whatever started the app.
  void consumeLaunch() {
    final r = _launch;
    _launch = null;
    if (r != null) _onResponse(r);
    takeBubbleLaunch();
  }

  void _onResponse(NotificationResponse r) {
    if (r.actionId == 'like' || r.actionId == 'reply') {
      _runAction(r).then((_) => AppState.I.refreshBadges());
      return;
    }
    _openPayload(r.payload);
  }
}
