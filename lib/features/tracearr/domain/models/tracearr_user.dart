import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';

/// A person's account on one server.
final class TracearrAccount {
  const TracearrAccount({
    required this.serverId,
    this.serverType = TracearrServerType.unknown,
    this.serverUserId,
    this.externalUserId,
    this.username = '',
    this.removedAt,
  });

  factory TracearrAccount.fromJson(TracearrJson json) => TracearrAccount(
    serverId: json.requiredText('server_id'),
    serverType: TracearrServerType.fromWire(json['server_type']),
    serverUserId: json.text('server_user_id'),
    externalUserId: json.text('external_user_id'),
    username: json.text('username') ?? '',
    removedAt: json.time('removed_at'),
  );

  final String serverId;
  final TracearrServerType serverType;

  /// Tracearr's id of the account.
  final String? serverUserId;

  /// The id of the user on the media server itself: what a Jellyfin or Emby
  /// user list matches on to link a person to their page here.
  final String? externalUserId;

  final String username;

  /// Set when the person was removed from that server. Their history stays.
  final DateTime? removedAt;

  bool get isRemoved => removedAt != null;

  @override
  String toString() => 'TracearrAccount(${serverType.name})';
}

/// One person across every server Tracearr watches.
///
/// Names and emails are theirs: [toString] prints none of it.
final class TracearrUser {
  const TracearrUser({
    required this.id,
    this.username = '',
    this.identityName,
    this.email,
    this.plexAccountId,
    this.accounts = const [],
  });

  factory TracearrUser.fromJson(TracearrJson json) => TracearrUser(
    id: json.requiredText('id'),
    username: json.text('username') ?? '',
    identityName: json.text('identity_name'),
    email: json.text('email'),
    plexAccountId: json.text('plex_account_id'),
    accounts: tracearrRows(json['accounts'], TracearrAccount.fromJson).rows,
  );

  final String id;
  final String username;

  /// The name the owner gave the person, when they did. Preferred for display.
  final String? identityName;

  final String? email;
  final String? plexAccountId;
  final List<TracearrAccount> accounts;

  String get displayName => identityName ?? username;

  /// Accounts still on a server.
  List<TracearrAccount> get activeAccounts => [
    for (final account in accounts)
      if (!account.isRemoved) account,
  ];

  /// Whether the person has no account left on any server.
  bool get isRemoved =>
      accounts.isNotEmpty && accounts.every((a) => a.isRemoved);

  @override
  String toString() => 'TracearrUser($id)';
}

/// Plays and time over one window.
final class TracearrPlayWindow {
  const TracearrPlayWindow({this.plays = 0, this.watchTimeMs = 0});

  factory TracearrPlayWindow.fromJson(TracearrJson? json) => TracearrPlayWindow(
    plays: json?.integer('plays') ?? 0,
    watchTimeMs: json?.integer('watch_time_ms') ?? 0,
  );

  final int plays;
  final int watchTimeMs;

  Duration get watchTime => Duration(milliseconds: watchTimeMs);
}

final class TracearrGenreCount {
  const TracearrGenreCount({required this.genre, this.plays = 0});

  factory TracearrGenreCount.fromJson(TracearrJson json) => TracearrGenreCount(
    genre: json.requiredText('genre'),
    plays: json.integer('plays') ?? 0,
  );

  final String genre;
  final int plays;
}

/// `GET /api/v2/public/users/{id}/stats`.
final class TracearrUserStats {
  const TracearrUserStats({
    this.userId,
    this.last7 = const TracearrPlayWindow(),
    this.last30 = const TracearrPlayWindow(),
    this.allTime = const TracearrPlayWindow(),
    this.topGenres = const [],
  });

  /// A body that is not an object is a [FormatException]: wrong answer.
  factory TracearrUserStats.fromJson(Object? body) {
    final json = asTracearrJson(body);
    if (json == null) {
      throw const FormatException('Tracearr user stats is not an object');
    }
    final windows = json.object('windows');
    return TracearrUserStats(
      userId: json.text('user_id'),
      last7: TracearrPlayWindow.fromJson(windows?.object('last_7')),
      last30: TracearrPlayWindow.fromJson(windows?.object('last_30')),
      allTime: TracearrPlayWindow.fromJson(windows?.object('all_time')),
      topGenres: tracearrRows(
        json['top_genres'],
        TracearrGenreCount.fromJson,
      ).rows,
    );
  }

  final String? userId;
  final TracearrPlayWindow last7;
  final TracearrPlayWindow last30;
  final TracearrPlayWindow allTime;

  /// Most played first, as Tracearr sorts them.
  final List<TracearrGenreCount> topGenres;

  @override
  String toString() => 'TracearrUserStats()';
}
