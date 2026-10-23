import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The floating chat head that sits over every app. It is drawn natively by
/// BubbleService (see tool/patch_android.py); Dart only switches it on and off
/// and feeds it through shared preferences, which also works from the
/// background listener where no screen exists.
class Bubble {
  Bubble._();
  static const _ch = MethodChannel('io.helphive/bubble');

  static Future<bool> canDraw() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('canDraw') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestDraw() async {
    try {
      await _ch.invokeMethod('requestDraw');
    } catch (_) {}
  }

  static Future<void> requestBatteryExemption() async {
    try {
      await _ch.invokeMethod('batteryExempt');
    } catch (_) {}
  }

  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    final p = await SharedPreferences.getInstance();
    await p.reload(); // the bubble itself switches this off when it is dragged to the X
    return p.getBool('bubble_enabled') ?? false;
  }

  /// Returns false when the "display over other apps" permission is missing; the
  /// system screen for it is opened so the person can allow it.
  static Future<bool> setEnabled(bool on) async {
    if (!Platform.isAndroid) return false;
    final p = await SharedPreferences.getInstance();
    if (on) {
      if (!await canDraw()) {
        await p.setBool('bubble_enabled', false);
        await requestDraw();
        return false;
      }
      await p.setBool('bubble_enabled', true);
      try {
        await _ch.invokeMethod('start');
      } catch (_) {}
    } else {
      await p.setBool('bubble_enabled', false);
      try {
        await _ch.invokeMethod('stop');
      } catch (_) {}
    }
    return true;
  }

  /// Brings the bubble up after launch / sign-in when it is switched on.
  static Future<void> resume() async {
    if (await isEnabled() && await canDraw()) {
      try {
        await _ch.invokeMethod('start');
      } catch (_) {}
    }
  }

  /// Removes the bubble without touching the on/off setting (sign-out).
  static Future<void> hide() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  /// Payload of the last tap on the bubble (or null), to open the right chat.
  static Future<String?> takeLaunch() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('takeLaunch');
    } catch (_) {
      return null;
    }
  }

  // ---- feeding the bubble (runs in the background listener)
  static Future<void> publish({
    required int unread,
    Map<String, dynamic>? head,
    Map<String, dynamic>? preview,
    String? latest,
    List<Map<String, dynamic>>? convs,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (convs != null) await p.setString('bubble_convs', jsonEncode(convs));
    await p.setString('bubble_head', jsonEncode(head ?? const {}));
    await p.setString('bubble_latest', latest ?? '');
    if (preview != null) await p.setString('bubble_preview', jsonEncode(preview));
    await p.setInt('bubble_unread', unread);
  }

  // ---- the bubble's pop-up chat window (drawn natively, see BubbleService)

  /// The chat list shown in the window.
  static Future<void> publishConvs(List<Map<String, dynamic>> convs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('bubble_convs', jsonEncode(convs));
  }

  /// The open conversation: its latest messages, plus which of the messages the
  /// window sent have gone through (`acked`) or not (`failed`).
  static Future<void> publishThread(Map<String, dynamic> thread) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('bubble_thread', jsonEncode(thread));
  }

  static Future<bool> listenerEnabled() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p.getBool('listener_enabled') ?? true;
  }

  static Future<void> setListenerEnabled(bool on) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('listener_enabled', on);
  }
}
