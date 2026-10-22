import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Everything stored in Neon (comments, messages, notifications) goes through the
/// Node server on Render. Each call carries the signed-in user's Supabase token.
class Api {
  Api._();
  static final _client = http.Client();
  static GoTrueClient get _auth => Supabase.instance.client.auth;

  static Future<dynamic> _send(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final session = _auth.currentSession;
      if (session == null) throw ApiException('Please sign in again.', 401);

      final uri = Uri.parse('${Config.apiUrl}$path').replace(queryParameters: (query?.isEmpty ?? true) ? null : query);
      final req = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer ${session.accessToken}'
        ..headers['Accept'] = 'application/json';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }

      http.Response res;
      try {
        res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 45)));
      } on TimeoutException {
        throw ApiException('The server is waking up. Give it a few seconds and try again.');
      } on SocketException {
        throw ApiException('No connection. Check your internet and try again.');
      } on http.ClientException {
        throw ApiException('No connection. Check your internet and try again.');
      }

      if (res.statusCode == 401 && attempt == 0) {
        try {
          await _auth.refreshSession();
        } catch (_) {}
        continue;
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.statusCode == 204 || res.body.isEmpty) return null;
        return jsonDecode(res.body);
      }
      var msg = 'Something went wrong (${res.statusCode}).';
      try {
        final m = (jsonDecode(res.body) as Map)['error'];
        if (m is String && m.isNotEmpty) msg = m;
      } catch (_) {}
      throw ApiException(msg, res.statusCode);
    }
    throw ApiException('Please sign in again.', 401);
  }

  /// Free-tier servers sleep; ping early so the first real call is quick.
  static Future<void> wake() async {
    try {
      await _client.get(Uri.parse('${Config.apiUrl}/health')).timeout(const Duration(seconds: 40));
    } catch (_) {}
  }

  // comments
  static Future<List<Comment>> comments(String postId) async {
    final r = await _send('GET', '/posts/$postId/comments') as Map<String, dynamic>;
    return (r['comments'] as List).map((e) => Comment.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Map<String, int>> commentCounts(List<String> postIds) async {
    if (postIds.isEmpty) return {};
    final r = await _send('POST', '/comments/counts', body: {'postIds': postIds}) as Map<String, dynamic>;
    return (r['counts'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()));
  }

  /// Comment totals and each post's helpful answer, for a page of feed posts.
  static Future<({Map<String, int> counts, Map<String, HelpfulPreview> helpful})> postExtras(List<String> postIds) async {
    if (postIds.isEmpty) return (counts: <String, int>{}, helpful: <String, HelpfulPreview>{});
    final r = await _send('POST', '/comments/counts', body: {'postIds': postIds}) as Map<String, dynamic>;
    return (
      counts: ((r['counts'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
      helpful: ((r['helpful'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, HelpfulPreview.fromJson(v as Map<String, dynamic>))),
    );
  }

  static Future<Comment> addComment(String postId, String body, {String? parentId}) async {
    final r = await _send('POST', '/posts/$postId/comments', body: {'body': body, if (parentId != null) 'parentId': parentId});
    return Comment.fromJson((r as Map<String, dynamic>)['comment'] as Map<String, dynamic>);
  }

  static Future<Comment> editComment(String id, String body) async {
    final r = await _send('PUT', '/comments/$id', body: {'body': body});
    return Comment.fromJson((r as Map<String, dynamic>)['comment'] as Map<String, dynamic>);
  }

  static Future<void> deleteComment(String id) => _send('DELETE', '/comments/$id');

  static Future<void> reactComment(String id, String? kind) => _send('PUT', '/comments/$id/reaction', body: {'kind': kind});

  // helpful stars. Only the poster can star a comment (the server checks).
  static Future<({bool helpful, int stars, bool postResolved})> setHelpful(String commentId, bool helpful) async {
    final r = await _send('PUT', '/comments/$commentId/helpful', body: {'helpful': helpful}) as Map<String, dynamic>;
    return (
      helpful: r['helpful'] as bool? ?? helpful,
      stars: (r['stars'] as num?)?.toInt() ?? 0,
      postResolved: r['postResolved'] as bool? ?? false,
    );
  }

  static Future<int> userStars(String userId) async {
    final r = await _send('GET', '/users/$userId/stars') as Map<String, dynamic>;
    return (r['stars'] as num?)?.toInt() ?? 0;
  }

  static Future<Map<String, int>> starsFor(List<String> userIds) async {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return {};
    final r = await _send('POST', '/users/stars', body: {'userIds': ids}) as Map<String, dynamic>;
    return ((r['stars'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt()));
  }

  /// Comments this person got starred, newest star first, each with its post.
  static Future<({List<ResolvedItem> items, bool hasMore})> resolved(String userId, {DateTime? before}) async {
    final r = await _send('GET', '/users/$userId/resolved', query: {if (before != null) 'before': before.toUtc().toIso8601String()}) as Map<String, dynamic>;
    return (
      items: (r['items'] as List).map((e) => ResolvedItem.fromJson(e as Map<String, dynamic>)).toList(),
      hasMore: r['hasMore'] as bool? ?? false,
    );
  }

  // conversations + messages
  static Future<List<Conversation>> conversations() async {
    final r = await _send('GET', '/conversations') as Map<String, dynamic>;
    return (r['conversations'] as List).map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<String> openConversation(String userId) async {
    final r = await _send('POST', '/conversations', body: {'userId': userId}) as Map<String, dynamic>;
    return r['id'] as String;
  }

  static Future<({List<Message> messages, bool hasMore, DateTime? otherReadAt})> messages(String conversationId, {DateTime? before}) async {
    final r = await _send('GET', '/conversations/$conversationId/messages',
        query: {'limit': '40', if (before != null) 'before': before.toUtc().toIso8601String()}) as Map<String, dynamic>;
    final read = r['otherReadAt'] as String?;
    return (
      messages: (r['messages'] as List).map((e) => Message.fromJson(e as Map<String, dynamic>)).toList(),
      hasMore: r['hasMore'] as bool? ?? false,
      otherReadAt: read == null ? null : DateTime.parse(read).toLocal(),
    );
  }

  static Future<void> sendMessage(String conversationId, String body, {String? replyTo}) =>
      _send('POST', '/conversations/$conversationId/messages', body: {'body': body, if (replyTo != null) 'replyTo': replyTo});

  static Future<void> markRead(String conversationId) => _send('POST', '/conversations/$conversationId/read');
  static Future<void> unsend(String messageId) => _send('DELETE', '/messages/$messageId');
  static Future<void> reactMessage(String id, String? kind) => _send('PUT', '/messages/$id/reaction', body: {'kind': kind});

  // notifications
  static Future<({List<Notif> items, bool hasMore})> notifications({DateTime? before}) async {
    final r = await _send('GET', '/notifications', query: {if (before != null) 'before': before.toUtc().toIso8601String()}) as Map<String, dynamic>;
    return (
      items: (r['notifications'] as List).map((e) => Notif.fromJson(e as Map<String, dynamic>)).toList(),
      hasMore: r['hasMore'] as bool? ?? false,
    );
  }

  static Future<({int notifications, int messages})> badges() async {
    final r = await _send('GET', '/badges') as Map<String, dynamic>;
    return (notifications: (r['notifications'] as num).toInt(), messages: (r['messages'] as num).toInt());
  }

  static Future<void> readAllNotifications() => _send('POST', '/notifications/read');
  static Future<void> readNotification(String id) => _send('POST', '/notifications/$id/read');
  static Future<void> deleteNotification(String id) => _send('DELETE', '/notifications/$id');
  static Future<void> deleteAllNotifications() => _send('DELETE', '/notifications');

  // events the server verifies against Supabase before notifying
  static Future<void> friendshipEvent(String userId) => _send('POST', '/events/friendship', body: {'userId': userId});
  static Future<void> postReactionEvent(String postId) => _send('POST', '/events/post-reaction', body: {'postId': postId});

  // deletes
  static Future<void> deletePost(String id) => _send('DELETE', '/posts/$id');
  static Future<void> deleteAccount() => _send('DELETE', '/me');
}
