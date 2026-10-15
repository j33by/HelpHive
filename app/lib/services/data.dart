import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'api.dart';

SupabaseClient get sb => Supabase.instance.client;
String get myId => sb.auth.currentUser!.id;

/// Turns library errors into something a person can read.
String friendly(Object e) {
  if (e is ApiException) return e.message;
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'That email and password do not match.';
    if (m.contains('already registered') || m.contains('already been registered')) return 'That email already has an account. Try signing in.';
    if (m.contains('email not confirmed')) return 'Confirm your email first. Check your inbox for the link.';
    if (m.contains('rate limit') || e.statusCode == '429') return 'Too many attempts. Wait a minute and try again.';
    if (m.contains('password')) return e.message;
    return e.message;
  }
  if (e is PostgrestException) {
    if (e.code == '23505') return 'That username is already taken.';
    if (e.code == '23514') return 'Some of that text is not allowed. Check the lengths and characters.';
    if (e.code == 'P0001') return e.message;
    if (e.code == '42501') return 'You are not allowed to do that.';
    return 'The server said no. Please try again.';
  }
  if (e is StorageException) {
    if (e.statusCode == '413') return 'That picture is too large.';
    return 'Could not upload the picture.';
  }
  if (e is SocketException) return 'No connection. Check your internet and try again.';
  return 'Something went wrong. Please try again.';
}

class PostsPage {
  PostsPage(this.posts, this.hasMore);
  final List<Post> posts;
  final bool hasMore;
}

class Data {
  Data._();
  static const pageSize = 15;
  static final _rng = Random.secure();

  static String? _postUrl(String path) => sb.storage.from('posts').getPublicUrl(path);

  // ---- posts
  static Future<PostsPage> feed({DateTime? before, String? author, String? search, String? category}) async {
    final rows = await sb.rpc('get_feed', params: {
      'p_limit': pageSize,
      if (before != null) 'p_before': before.toUtc().toIso8601String(),
      if (author != null) 'p_author': author,
      if (search != null && search.trim().isNotEmpty) 'p_search': search.trim(),
      if (category != null) 'p_category': category,
    }) as List;
    final posts = rows.map((r) => Post.fromRow(r as Map<String, dynamic>, _postUrl)).toList();
    await _attachCounts(posts);
    return PostsPage(posts, posts.length >= pageSize);
  }

  static Future<Post?> post(String id) async {
    final rows = await sb.rpc('get_feed', params: {'p_id': id, 'p_limit': 1}) as List;
    if (rows.isEmpty) return null;
    final p = Post.fromRow(rows.first as Map<String, dynamic>, _postUrl);
    await _attachCounts([p]);
    return p;
  }

  static Future<void> _attachCounts(List<Post> posts) async {
    try {
      final counts = await Api.commentCounts(posts.map((p) => p.id).toList());
      for (final p in posts) {
        p.commentCount = counts[p.id] ?? 0;
      }
    } catch (_) {
      // the feed is still useful without comment totals
    }
  }

  static Future<void> createPost({required String body, required String category, Uint8List? image, String? ext}) async {
    String? path;
    if (image != null) path = await _upload('posts', image, ext);
    try {
      await sb.from('posts').insert({'body': body.trim(), 'category': category, if (path != null) 'image_path': path});
    } catch (e) {
      if (path != null) _quietRemove('posts', path);
      rethrow;
    }
  }

  static Future<void> updatePost(Post p, {required String body, required String category, required bool removeImage, Uint8List? newImage, String? ext}) async {
    String? path = p.imagePath;
    String? oldToDrop;
    if (newImage != null) {
      oldToDrop = path;
      path = await _upload('posts', newImage, ext);
    } else if (removeImage) {
      oldToDrop = path;
      path = null;
    }
    try {
      await sb.from('posts').update({'body': body.trim(), 'category': category, 'image_path': path}).eq('id', p.id);
    } catch (e) {
      if (newImage != null && path != null) _quietRemove('posts', path);
      rethrow;
    }
    if (oldToDrop != null) _quietRemove('posts', oldToDrop);
  }

  static Future<void> setResolved(Post p, bool value) async {
    await sb.from('posts').update({'is_resolved': value}).eq('id', p.id);
    p.isResolved = value;
  }

  static Future<void> react(String postId, String? kind) async {
    await sb.rpc('set_post_reaction', params: {'p_post': postId, 'p_kind': kind});
    Api.postReactionEvent(postId).catchError((_) {});
  }

  // ---- people
  static Future<List<Person>> people({String filter = 'all', String? query, int offset = 0, int limit = 40}) async {
    final rows = await sb.rpc('get_people', params: {
      'p_filter': filter,
      if (query != null && query.trim().isNotEmpty) 'p_query': query.trim(),
      'p_limit': limit,
      'p_offset': offset,
    }) as List;
    return rows.map((r) => Person.fromRow(r as Map<String, dynamic>)).toList();
  }

  static Future<Profile> profile(String id) async {
    final rows = await sb.rpc('get_profile_card', params: {'p_id': id}) as List;
    if (rows.isEmpty) throw ApiException('That profile could not be found.', 404);
    return Profile.fromRow(rows.first as Map<String, dynamic>);
  }

  // ---- friendships; each change is followed by a ping so the server can notify
  static Future<String?> addFriend(String userId) async {
    final id = await sb.rpc('send_friend_request', params: {'p_user': userId});
    Api.friendshipEvent(userId).catchError((_) {});
    return id as String?;
  }

  static Future<void> respond(String friendshipId, String otherId, bool accept) async {
    await sb.rpc('respond_friend_request', params: {'p_id': friendshipId, 'p_accept': accept});
    Api.friendshipEvent(otherId).catchError((_) {});
  }

  static Future<void> removeFriendship(String friendshipId, String otherId) async {
    await sb.rpc('remove_friendship', params: {'p_id': friendshipId});
    Api.friendshipEvent(otherId).catchError((_) {});
  }

  // ---- profile editing
  static Future<void> updateProfile({required String username, required String fullName, required String bio, required String location}) async {
    await sb.from('profiles').update({
      'username': username.trim().toLowerCase(),
      'full_name': fullName.trim(),
      'bio': bio.trim(),
      'location': location.trim(),
    }).eq('id', myId);
  }

  static Future<String> setPicture({required bool cover, required Uint8List bytes, String? ext, String? oldUrl}) async {
    final bucket = cover ? 'covers' : 'avatars';
    final path = await _upload(bucket, bytes, ext);
    final url = sb.storage.from(bucket).getPublicUrl(path);
    try {
      await sb.from('profiles').update({cover ? 'cover_url' : 'avatar_url': url}).eq('id', myId);
    } catch (e) {
      _quietRemove(bucket, path);
      rethrow;
    }
    final marker = '/object/public/$bucket/';
    if (oldUrl != null && oldUrl.contains(marker)) {
      _quietRemove(bucket, Uri.decodeComponent(oldUrl.split(marker).last));
    }
    return url;
  }

  static Future<void> clearCover(String? oldUrl) async {
    await sb.from('profiles').update({'cover_url': null}).eq('id', myId);
    const marker = '/object/public/covers/';
    if (oldUrl != null && oldUrl.contains(marker)) {
      _quietRemove('covers', Uri.decodeComponent(oldUrl.split(marker).last));
    }
  }

  // ---- storage
  static String _name() {
    final b = List<int>.generate(10, (_) => _rng.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> _upload(String bucket, Uint8List bytes, String? ext) async {
    final e = switch ((ext ?? 'jpg').toLowerCase()) { 'png' => 'png', 'webp' => 'webp', _ => 'jpg' };
    final mime = e == 'jpg' ? 'image/jpeg' : 'image/$e';
    final path = '$myId/${DateTime.now().millisecondsSinceEpoch}_${_name()}.$e';
    await sb.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
    return path;
  }

  static void _quietRemove(String bucket, String path) {
    sb.storage.from(bucket).remove([path]).catchError((_) => <FileObject>[]);
  }
}
