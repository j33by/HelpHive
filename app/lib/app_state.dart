import 'dart:async';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'services/alerts.dart';
import 'services/api.dart';
import 'services/data.dart';

/// Signed-in user, tab badges and the current tab. One instance for the app.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  Profile? me;
  int notifBadge = 0;
  int msgBadge = 0;
  Standing standing = Standing();
  bool standingReady = false;
  int _tick = 0;
  final tab = ValueNotifier<int>(0);
  Timer? _timer;

  Future<void> start() async {
    Api.wake();
    standingReady = false;
    // never hold the app hostage to a sleeping server: after 4 s carry on as normal
    Future.delayed(const Duration(seconds: 4), () {
      if (!standingReady) {
        standingReady = true;
        notifyListeners();
      }
    });
    Alerts.I.startListener();
    await refreshStanding(launch: true);
    await refreshMe();
    await refreshBadges(force: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _tick++;
      // check often while limited (to notice a lift or an unban quickly), rarely otherwise
      if (standing.status != 'active' || _tick % 3 == 0) refreshStanding();
      if (!standing.banned) refreshBadges();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    me = null;
    notifBadge = 0;
    msgBadge = 0;
    standing = Standing();
    standingReady = false;
    tab.value = 0;
    Alerts.I.stopListener();
  }

  Future<void> refreshStanding({bool launch = false}) async {
    try {
      final s = await Api.standing(launch: launch);
      final changed = s.status != standing.status || s.until != standing.until || s.strikes != standing.strikes ||
          s.appeal?.status != standing.appeal?.status || s.history.length != standing.history.length;
      standing = s;
      if (changed || !standingReady) {
        standingReady = true;
        notifyListeners();
      }
    } catch (_) {
      if (!standingReady) {
        standingReady = true;
        notifyListeners();
      }
    }
  }

  Future<void> refreshMe() async {
    try {
      me = await Data.profile(myId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshBadges({bool force = false}) async {
    try {
      final b = await Api.badges();
      final moreAlerts = b.notifications > notifBadge;
      final moreMsgs = b.messages > msgBadge;
      if (!force && (moreAlerts || moreMsgs)) Alerts.I.onBadgeGrowth(messages: moreMsgs, alerts: moreAlerts);
      if (force || b.notifications != notifBadge || b.messages != msgBadge) {
        notifBadge = b.notifications;
        msgBadge = b.messages;
        notifyListeners();
      }
    } catch (_) {}
  }

  void setBadges({int? notifications, int? messages}) {
    notifBadge = notifications ?? notifBadge;
    msgBadge = messages ?? msgBadge;
    notifyListeners();
  }
}
