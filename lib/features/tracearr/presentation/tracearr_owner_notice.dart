import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_client.dart';

/// What a step of signing in as Tracearr's owner can say when it stops, and
/// what to do next: the words of the owner's access, in one place.
///
/// Each comes from what answered (Tracearr's own refusals as typed
/// exceptions, the transport's classification) and never from an exception's
/// text, and none carries a password, a token, a cookie or an address.
enum TracearrOwnerNoticeKind {
  /// The name, email or password is not right.
  wrongPassword,

  /// The account is real and may not sign in here.
  notAllowed,

  /// Tracearr rate-limits sign-in.
  tooManyTries,

  /// The session is a member's or an administrator's.
  notOwner,

  /// Single sign-on is the only way in, and Cupola cannot complete it.
  singleSignOn,

  /// Nothing Cupola can use is turned on.
  turnedOff,

  /// Tracearr has no owner yet.
  notSetUp,

  /// The Plex page was not approved in time.
  plexTimedOut,

  /// The saved session ended.
  signedOut,

  /// Anything else, in the classification's own words.
  other,
}

@immutable
class TracearrOwnerNotice {
  const TracearrOwnerNotice._(
    this.kind, {
    required this.tone,
    required this.title,
    this.sentence,
    this.retryHelps = false,
  });

  /// Why a step stopped, from [error].
  factory TracearrOwnerNotice.of(Object error) {
    if (error is TracearrNotOwner) return notOwner;
    if (error is TracearrOwnerSessionEnded) return signedOut;
    if (error is TracearrSignInRefused) {
      return switch (error.refusal) {
        TracearrSignInRefusal.wrongPassword => wrongPassword,
        TracearrSignInRefusal.notAllowed => notAllowed,
        TracearrSignInRefusal.tooManyTries => tooManyTries,
        TracearrSignInRefusal.notSetUp => notSetUp,
      };
    }
    final reason = classifyConnectionFailure(error);
    return TracearrOwnerNotice._(
      TracearrOwnerNoticeKind.other,
      tone: failureTone(reason),
      title: failureHeadline(
        reason,
        subject: 'Tracearr',
        gateway: accessGatewayOf(error),
      ),
      sentence: connectionFailureSentence(
        error,
        remedyBeside: true,
        subject: 'Tracearr',
      ),
      retryHelps: failureRetryHelps(reason),
    );
  }

  /// What a Tracearr whose ways are read says when there is nothing to sign in
  /// with; null when there is.
  static TracearrOwnerNotice? ofWays(TracearrOwnerWays ways) {
    if (ways.needsSetup) return notSetUp;
    if (ways.oidcOnly) return singleSignOn;
    if (ways.none) return turnedOff;
    return null;
  }

  static const wrongPassword = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.wrongPassword,
    tone: StatusTone.warning,
    title: "That name or email and password didn't work",
    sentence: 'Check them and sign in again.',
  );

  static const notAllowed = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.notAllowed,
    tone: StatusTone.warning,
    title: "This account can't sign in to Tracearr",
    sentence: "Only the owner's account can.",
  );

  static const tooManyTries = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.tooManyTries,
    tone: StatusTone.warning,
    title: 'Too many tries',
    sentence: 'Wait a moment, then sign in again.',
    retryHelps: true,
  );

  static const notOwner = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.notOwner,
    tone: StatusTone.info,
    title: 'Only the owner can acknowledge',
    sentence: "Sign in with the owner's account.",
  );

  /// Said once, with its remedy, where the owner's way in would be offered.
  static const singleSignOn = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.singleSignOn,
    tone: StatusTone.info,
    title:
        "This Tracearr signs in with single sign-on, which Cupola can't use.",
    sentence: 'Acknowledge it in Tracearr.',
  );

  static const turnedOff = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.turnedOff,
    tone: StatusTone.info,
    title: 'This Tracearr has password and Plex sign-in turned off',
    sentence: 'Acknowledge it in Tracearr.',
  );

  static const notSetUp = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.notSetUp,
    tone: StatusTone.info,
    title: "This Tracearr isn't set up yet",
    sentence: 'Whoever runs it needs to create the owner first.',
  );

  static const plexTimedOut = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.plexTimedOut,
    tone: StatusTone.info,
    title: 'The Plex sign-in timed out',
  );

  /// The saved session ended: the words the classification has for it, blue.
  static final signedOut = TracearrOwnerNotice._(
    TracearrOwnerNoticeKind.signedOut,
    tone: failureTone(ServiceFailureReason.sessionEnded),
    title: failureHeadline(
      ServiceFailureReason.sessionEnded,
      subject: 'Tracearr',
    ),
    // Not the classification's sentence, which speaks of asking for movies
    // and series: what signing in again is for here is the owner's two writes.
    sentence: 'Sign in as the owner again to acknowledge and dismiss.',
  );

  final TracearrOwnerNoticeKind kind;

  /// Red only when nothing answered; blue for a step that is the person's or
  /// the operator's, never a fault; amber for a fault.
  final StatusTone tone;

  final String title;
  final String? sentence;

  /// Whether sending the same request again can still change the answer.
  final bool retryHelps;

  /// The whole notice as one sentence, for a screen reader.
  String get spoken => sentence == null ? '$title.' : '$title. $sentence';

  @override
  bool operator ==(Object other) =>
      other is TracearrOwnerNotice &&
      other.kind == kind &&
      other.tone == tone &&
      other.title == title &&
      other.sentence == sentence &&
      other.retryHelps == retryHelps;

  @override
  int get hashCode => Object.hash(kind, tone, title, sentence, retryHelps);

  @override
  String toString() => 'TracearrOwnerNotice(${kind.name})';
}
