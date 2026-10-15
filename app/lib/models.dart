const reactionKinds = ['like', 'love', 'haha', 'wow', 'sad'];

DateTime _t(dynamic v) => DateTime.parse(v as String).toLocal();

/// Name + picture, as the API server sends them with comments, messages and notifications.
class UserLite {
  UserLite({required this.id, required this.username, required this.fullName, this.avatarUrl});
  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;

  String get display => fullName.trim().isEmpty ? username : fullName;

  factory UserLite.fromJson(Map<String, dynamic>? j) => j == null
      ? UserLite(id: '', username: 'deleted', fullName: 'Deleted user')
      : UserLite(
          id: j['id'] as String,
          username: j['username'] as String? ?? '',
          fullName: j['fullName'] as String? ?? '',
          avatarUrl: j['avatarUrl'] as String?,
        );
}

class Profile {
  Profile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.bio,
    required this.location,
    this.avatarUrl,
    this.coverUrl,
    required this.createdAt,
    this.postsCount = 0,
    this.friendsCount = 0,
    this.friendshipId,
    this.relation = 'none',
  });
  final String id;
  String username;
  String fullName;
  String bio;
  String location;
  String? avatarUrl;
  String? coverUrl;
  final DateTime createdAt;
  int postsCount;
  int friendsCount;
  String? friendshipId;
  String relation; // self | none | friends | sent | received

  String get display => fullName.trim().isEmpty ? username : fullName;

  factory Profile.fromRow(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        username: j['username'] as String,
        fullName: j['full_name'] as String? ?? '',
        bio: j['bio'] as String? ?? '',
        location: j['location'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        coverUrl: j['cover_url'] as String?,
        createdAt: _t(j['created_at']),
        postsCount: (j['posts_count'] as num?)?.toInt() ?? 0,
        friendsCount: (j['friends_count'] as num?)?.toInt() ?? 0,
        friendshipId: j['friendship_id'] as String?,
        relation: j['relation'] as String? ?? 'none',
      );
}

class Person {
  Person({
    required this.id,
    required this.username,
    required this.fullName,
    required this.bio,
    this.avatarUrl,
    this.friendshipId,
    this.relation = 'none',
  });
  final String id;
  final String username;
  final String fullName;
  final String bio;
  final String? avatarUrl;
  String? friendshipId;
  String relation; // none | friends | sent | received

  String get display => fullName.trim().isEmpty ? username : fullName;

  UserLite get lite => UserLite(id: id, username: username, fullName: fullName, avatarUrl: avatarUrl);

  factory Person.fromRow(Map<String, dynamic> j) => Person(
        id: j['id'] as String,
        username: j['username'] as String,
        fullName: j['full_name'] as String? ?? '',
        bio: j['bio'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        friendshipId: j['friendship_id'] as String?,
        relation: j['relation'] as String? ?? 'none',
      );
}

class Post {
  Post({
    required this.id,
    required this.authorId,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    required this.body,
    this.imagePath,
    this.imageUrl,
    required this.category,
    required this.isResolved,
    required this.createdAt,
    required this.updatedAt,
    required this.reactionCount,
    this.myReaction,
    this.commentCount = 0,
  });
  final String id;
  final String authorId;
  final String username;
  final String fullName;
  final String? avatarUrl;
  String body;
  String? imagePath;
  String? imageUrl;
  String category; // general | request | offer
  bool isResolved;
  final DateTime createdAt;
  DateTime updatedAt;
  int reactionCount;
  String? myReaction;
  int commentCount;

  String get display => fullName.trim().isEmpty ? username : fullName;
  bool get edited => updatedAt.difference(createdAt).inSeconds > 5;

  factory Post.fromRow(Map<String, dynamic> j, String? Function(String path) urlFor) {
    final path = j['image_path'] as String?;
    return Post(
      id: j['id'] as String,
      authorId: j['author_id'] as String,
      username: j['username'] as String,
      fullName: j['full_name'] as String? ?? '',
      avatarUrl: j['avatar_url'] as String?,
      body: j['body'] as String? ?? '',
      imagePath: path,
      imageUrl: path == null ? null : urlFor(path),
      category: j['category'] as String? ?? 'general',
      isResolved: j['is_resolved'] as bool? ?? false,
      createdAt: _t(j['created_at']),
      updatedAt: _t(j['updated_at']),
      reactionCount: (j['reaction_count'] as num?)?.toInt() ?? 0,
      myReaction: j['my_reaction'] as String?,
    );
  }
}

class Comment {
  Comment({
    required this.id,
    required this.postId,
    this.parentId,
    required this.user,
    required this.body,
    required this.edited,
    required this.createdAt,
    required this.reactionCount,
    this.myReaction,
  });
  final String id;
  final String postId;
  final String? parentId;
  final UserLite user;
  String body;
  bool edited;
  final DateTime createdAt;
  int reactionCount;
  String? myReaction;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['id'] as String,
        postId: j['postId'] as String,
        parentId: j['parentId'] as String?,
        user: UserLite.fromJson(j['user'] as Map<String, dynamic>?),
        body: j['body'] as String,
        edited: j['edited'] as bool? ?? false,
        createdAt: _t(j['createdAt']),
        reactionCount: (j['reactionCount'] as num?)?.toInt() ?? 0,
        myReaction: j['myReaction'] as String?,
      );
}

class Conversation {
  Conversation({
    required this.id,
    required this.user,
    required this.lastBody,
    required this.lastMine,
    required this.lastDeleted,
    required this.lastAt,
    required this.unread,
  });
  final String id;
  final UserLite user;
  final String lastBody;
  final bool lastMine;
  final bool lastDeleted;
  final DateTime lastAt;
  final int unread;

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final lm = j['lastMessage'] as Map<String, dynamic>;
    return Conversation(
      id: j['id'] as String,
      user: UserLite.fromJson(j['user'] as Map<String, dynamic>?),
      lastBody: lm['body'] as String? ?? '',
      lastMine: lm['mine'] as bool? ?? false,
      lastDeleted: lm['deleted'] as bool? ?? false,
      lastAt: _t(j['lastMessageAt']),
      unread: (j['unread'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReplyRef {
  ReplyRef({required this.id, required this.body, required this.senderId, required this.deleted});
  final String id;
  final String body;
  final String senderId;
  final bool deleted;
}

class Message {
  Message({
    required this.id,
    required this.senderId,
    required this.body,
    required this.deleted,
    required this.createdAt,
    this.replyTo,
    required this.reactions,
    this.myReaction,
    this.pending = false,
  });
  final String id;
  final String senderId;
  String body;
  bool deleted;
  final DateTime createdAt;
  final ReplyRef? replyTo;
  Map<String, int> reactions;
  String? myReaction;
  bool pending;

  factory Message.fromJson(Map<String, dynamic> j) {
    final r = j['replyTo'] as Map<String, dynamic>?;
    final raw = (j['reactions'] as Map?) ?? const {};
    return Message(
      id: j['id'] as String,
      senderId: j['senderId'] as String,
      body: j['body'] as String? ?? '',
      deleted: j['deleted'] as bool? ?? false,
      createdAt: _t(j['createdAt']),
      replyTo: r == null
          ? null
          : ReplyRef(
              id: r['id'] as String,
              body: r['body'] as String? ?? '',
              senderId: r['senderId'] as String? ?? '',
              deleted: r['deleted'] as bool? ?? false,
            ),
      reactions: raw.map((k, v) => MapEntry(k as String, (v as num).toInt())),
      myReaction: j['myReaction'] as String?,
    );
  }
}

class Notif {
  Notif({
    required this.id,
    required this.type,
    required this.actor,
    this.postId,
    this.commentId,
    this.snippet,
    required this.read,
    required this.createdAt,
  });
  final String id;
  final String type;
  final UserLite actor;
  final String? postId;
  final String? commentId;
  final String? snippet;
  bool read;
  final DateTime createdAt;

  factory Notif.fromJson(Map<String, dynamic> j) => Notif(
        id: j['id'] as String,
        type: j['type'] as String,
        actor: UserLite.fromJson(j['actor'] as Map<String, dynamic>?),
        postId: j['postId'] as String?,
        commentId: j['commentId'] as String?,
        snippet: j['snippet'] as String?,
        read: j['read'] as bool? ?? false,
        createdAt: _t(j['createdAt']),
      );
}
