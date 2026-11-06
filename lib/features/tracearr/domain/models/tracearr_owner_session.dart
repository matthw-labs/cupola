import 'package:flutter/foundation.dart';

/// How the owner signed in to Tracearr.
enum TracearrOwnerKind {
  /// Tracearr's own email and password: `POST /api/v1/auth/sign-in/email`.
  email,

  /// Tracearr's own username and password: `/sign-in/username`.
  username,

  /// The owner's Plex account: Tracearr makes the PIN and checks it.
  plex;

  /// The kind [name] spells, or null for one this build does not know.
  static TracearrOwnerKind? byName(String? name) =>
      values.where((kind) => kind.name == name).firstOrNull;
}

/// The owner's session on a Tracearr connection.
///
/// A second credential beside the connection's public key, with its own job:
/// the key reads everything and is always there, and this one only writes what
/// the public API has no route for (acknowledging a violation and dismissing
/// it). Optional, so a connection without one is not half set up.
///
/// The password and the Plex token never live here: only the bearer Tracearr's
/// sign-in answered with ([token]) and what Cupola read about the account.
/// Signing out, or the server ending the session, empties [token] and keeps
/// the rest, so signing in again is one step.
@immutable
final class TracearrOwnerSession {
  const TracearrOwnerSession({
    required this.kind,
    this.login = '',
    this.displayName = '',
    this.token = '',
    this.expiresAt,
    this.checkedAt,
  });

  final TracearrOwnerKind kind;

  /// What the person typed to sign in: a name or an email. Not secret, so the
  /// form can be filled in again. Empty for Plex.
  final String login;

  /// The name Tracearr knows the owner by: `Signed in as Anna`.
  final String displayName;

  /// Secret: the bearer Tracearr's sign-in handed back (`set-auth-token`).
  /// Empty while signed out. Lives in secure storage, never beside the
  /// address.
  final String token;

  /// When Tracearr said the session ends, from its last `get-session`. Null
  /// before the first read.
  final DateTime? expiresAt;

  /// When the session was last proven or renewed: Better Auth moves a
  /// session's end 30 days past a request once the session is a day old, so
  /// one read a day keeps it alive.
  final DateTime? checkedAt;

  /// Whether a session is held: an owner without one is signed out.
  bool get isSignedIn => token.isNotEmpty;

  TracearrOwnerSession copyWith({
    String? login,
    String? displayName,
    String? token,
    DateTime? expiresAt,
    DateTime? checkedAt,
  }) => TracearrOwnerSession(
    kind: kind,
    login: login ?? this.login,
    displayName: displayName ?? this.displayName,
    token: token ?? this.token,
    expiresAt: expiresAt ?? this.expiresAt,
    checkedAt: checkedAt ?? this.checkedAt,
  );

  /// This owner signed out: the session gone, the rest kept.
  TracearrOwnerSession get signedOut =>
      TracearrOwnerSession(kind: kind, login: login, displayName: displayName);

  @override
  bool operator ==(Object other) =>
      other is TracearrOwnerSession &&
      other.kind == kind &&
      other.login == login &&
      other.displayName == displayName &&
      other.token == token &&
      other.expiresAt == expiresAt &&
      other.checkedAt == checkedAt;

  @override
  int get hashCode =>
      Object.hash(kind, login, displayName, token, expiresAt, checkedAt);

  /// The kind and the name only: never the token, never the login (an email
  /// is personal).
  @override
  String toString() => 'TracearrOwnerSession(${kind.name}, "$displayName")';
}
