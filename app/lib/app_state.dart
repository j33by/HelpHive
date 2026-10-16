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
  final tab = ValueNotifier<int>(0);
  Timer? _timer;

  Future<void> start() async {
    Api.wake();
    Alerts.I.startListener();
    await refreshMe();
    await refreshBadges(force: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => refreshBadges());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    me = null;
    notifBadge = 0;
    msgBadge = 0;
    tab.value = 0;
    Alerts.I.stopListener();
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
