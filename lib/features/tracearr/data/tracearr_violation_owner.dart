/// How a write on a violation ended, in the words the screen needs and no more.
///
/// An enum and not an exception, because every one of these is an expected
/// answer a person reads about, not a crash: the screen says one sentence for
/// each and decides what stays on the page.
enum TracearrOwnerOutcome {
  /// Tracearr did it.
  done,

  /// The owner's session ended or was refused. Not a fault: the person signs
  /// in again (blue, `Signed out of Tracearr`).
  signedOut,

  /// The session is a member's, and Tracearr only lets its owner do this
  /// (`Only the owner can acknowledge`).
  notOwner,

  /// Tracearr has no such violation any more: dismissed elsewhere, or by a
  /// second tap. Not a failure: there is nothing left to write on.
  gone,

  /// This Tracearr has no such route, or answered in a shape we do not read.
  /// The controls leave the page rather than promise what cannot be kept: the
  /// private API has no public contract, so this is an expected answer.
  unavailable,

  /// Anything else: the server could not do it, or did not answer.
  failed,
}

/// The two writes the public API does not have, which only the owner's session
/// can make (`PATCH` and `DELETE /api/v1/violations/:id`).
///
/// The violation screens depend on this and on nothing else about the owner:
/// they draw both controls from [tracearrViolationOwnerProvider], dimmed while
/// it holds no owner, and call these two methods when it does. The owner's
/// client (`TracearrOwnerClient`, one constructor, built from the connection's
/// reach) implements it, and the provider answers with it while a session is
/// held.
///
/// An implementation must never put a token, a cookie or a password in a log,
/// in [Object.toString] or in a failure's text, and must answer with an
/// outcome rather than throw for anything the server can say.
abstract interface class TracearrViolationOwner {
  /// Marks the violation as seen. Tracearr keeps it and its effect on the
  /// person's trust.
  Future<TracearrOwnerOutcome> acknowledge(String violationId);

  /// Removes the violation as a false positive, which also gives back the
  /// trust it cost the person.
  Future<TracearrOwnerOutcome> dismiss(String violationId);
}
