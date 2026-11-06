import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/settings/domain/unread_secret.dart'
    show secureStoreName;
import 'package:cupola/core/status/media_status.dart';

/// Why a connection attempt failed.
///
/// A bare "disconnected" cannot tell a wrong address apart from rejected
/// credentials, which leaves the user with a single generic "could not
/// connect" message and nothing to act on. This classifies the failure so the
/// UI can name the actual cause.
///
/// ## Red is one reason
///
/// [unreachable] is the reason nothing replied, and with [unreachableAtBoth],
/// the same silence at both of a connection's addresses, the only one painted
/// red ([failureTone]). Every other reason is something that *answered*: a
/// refusal, a 5xx, a reply nobody can read, a timeout after the connection was
/// made, or a request the device itself would not send, and each of those is
/// a **fault**: amber, with one concrete thing to go and fix. One is neither:
/// [sessionEnded] is a step that falls to the person, blue like a certificate
/// waiting to be trusted. Nor is [onlyAtHome], neutral: nothing was asked,
/// because the app is away from the only network that reaches it. A surface
/// decides nothing about tone or words on its
/// own; it asks [failureTone], [failureLabel], [failureHeadline] and
/// [failureRemedy].
enum ServiceFailureReason {
  /// Nothing replied at the address: DNS failure, connection refused, no
  /// route, a connection that never completed (Dio's connect timeout), or a
  /// deadline that passed with no reply and no proof the host was ever reached.
  unreachable,

  /// Nothing replied at either of the connection's two addresses: the route
  /// probe knocked at home and away together and neither answered
  /// (`unansweredConnectionsProvider`), and a request to the address in use
  /// went unanswered too ([ConnectionUnanswered] says where).
  ///
  /// [unreachable] said of both addresses, and red like it: the phone is
  /// offline, or the server is down. Never [onlyAtHome], which is a
  /// connection with one address, not asked.
  unreachableAtBoth,

  /// Reached the host, then it did not answer within the timeout. Only a
  /// timeout that proves the connection was made lands here: Dio's send and
  /// receive timeouts, or a client that knows it was talking to the server.
  timeout,

  /// The certificate did not verify: untrusted, expired or for another name
  /// (BoringSSL's `CERTIFICATE_VERIFY_FAILED`, on every platform).
  tls,

  /// The address says https and the port answered in plain http: the
  /// handshake met a reply that is not TLS at all (BoringSSL's
  /// `WRONG_VERSION_NUMBER`), the usual sign of an http port, like TrueNAS's
  /// 80 or 81 beside its HTTPS 443 or 8443.
  ///
  /// Amber: the server is there, and the address names the wrong port or
  /// scheme. Never [tls], whose remedy is trusting a certificate: no
  /// certificate was ever sent, so the probe finds nothing to trust and
  /// "test again" would loop.
  plainHttp,

  /// The secure connection broke off before any certificate arrived: the
  /// server closed it mid-handshake, or the two sides share no TLS version.
  /// Something is at the address, and it is not the https it names.
  ///
  /// Amber, never [tls]: there is no certificate to trust, and saying there
  /// is sends the person to look for one. When a plain http request to the
  /// same port answers, the connection test makes it [plainHttp].
  noSecureConnection,

  /// Reached the service, which rejected the credentials or the API key.
  unauthorized,

  /// Reached the service, which refused the address Cupola connects through,
  /// before it looked at any credential: qBittorrent's host header check (or a
  /// reverse proxy's) answers `401` before it checks the password. Retrying the same
  /// request fails the same way until its settings allow the address, so
  /// the remedy is in the service's settings, never a password. Amber, like
  /// every answer that is a fault rather than silence.
  addressRefused,

  /// A Seerr account's session is over: it expired after 30 days unused, it
  /// was signed out elsewhere, or the operator removed the account. The
  /// server refused a request and then `/auth/me` itself
  /// (`classifySeerrRefusal`).
  ///
  /// Blue, never amber: nothing in the stack is broken, and the one thing to
  /// do is the person's own, signing in again. Never [unauthorized] either,
  /// whose remedy is a key nobody pasted.
  sessionEnded,

  /// The connection has no address away from home and the app is away: at
  /// least one other connection moved to its address away because the one at
  /// home did not answer (`awayFromHomeProvider`). Nothing was asked, so
  /// nothing failed to answer: the request never left the device
  /// ([ServiceOnlyAtHome]).
  ///
  /// Neutral, never red and never in Needs you: a server reached only on the
  /// home network is a setup, not a fault (Q1, 13/10). The remedy is the
  /// operator's, an address away; no retry changes it.
  onlyAtHome,

  /// This device would not hand over the connection's saved secret: secure
  /// storage refused the read when the settings were loaded. Nothing was
  /// sent, so nothing answered or refused; amber, because there is one thing
  /// to do, and it is the refused key's: paste it again.
  secretUnread,

  /// Seerr's CSRF protection refused a write twice: once without a token,
  /// and again with the token the server had just handed out. A fault of the
  /// server's, amber, and the same write may still pass.
  ///
  /// A refusal the first time is not this: the transport fetches a token and
  /// sends the write again (`SeerrCsrfInterceptor`).
  csrfRefused,

  /// Reached a server, but the API is not at this URL: typically a base URL
  /// pointing at the wrong app, or a missing reverse-proxy subpath.
  notFound,

  /// Reached a server that answered with a redirect nothing here may follow:
  /// a `Location` pointing at another origin (following it would replay the
  /// API key to a host the user never configured), a 3xx with no `Location` at
  /// all, or a redirect loop.
  ///
  /// Distinct from [notFound] because the fix is different: the address is
  /// plausible and the server is answering, but something in front of the
  /// service is bouncing the request, and because it must never trigger a TLS
  /// probe: the handshake already succeeded.
  redirected,

  /// Something in front of the service answered in its place and asks for
  /// access the request did not carry, or refused the access it did: a
  /// Cloudflare Access application, a sign-in page, a proxy's password
  /// prompt. [AccessGatewayAnswer] says which.
  ///
  /// Distinct from [unauthorized], which is the service refusing its own key:
  /// here the service never saw the request, so pasting its key again cannot
  /// help, and neither can sending the same request again.
  accessGateway,

  /// The service answered with a 5xx.
  serverError,

  /// Something answered, with a body nobody can read: not JSON where JSON was
  /// asked for, typically a reverse proxy's HTML page.
  invalidResponse,

  /// The request was refused before it left the device because the address
  /// would carry the credential in cleartext: an `http://` TrueNAS, whose key
  /// the server revokes on sight when it arrives that way.
  ///
  /// Amber, and never red: nothing failed to answer, because nothing was
  /// dialled. And never a certificate or local-network question either; both
  /// probes would dial the very address this refused to dial.
  insecureTransport,

  /// The host OS refused to let Cupola onto the local network at all, so the
  /// request never left the device.
  ///
  /// Unreachable in every way that matters at the socket: iOS answers "no route
  /// to host", Android times out, which is why this is the one reason
  /// [classifyConnectionFailure] can never produce: no exception carries it.
  /// It is attributed afterwards, by asking the OS
  /// (`probeLocalNetworkAccess`), and it *supersedes* the socket's verdict
  /// because the address the user is being told to check was never dialled.
  localNetworkBlocked,

  /// Reached, failed, and the cause cannot be attributed: a 4xx no other
  /// reason covers, an error a client raised after the server replied.
  ///
  /// A fault, like everything that is not [unreachable]: "did not answer" is a
  /// claim about the host, and nothing here supports it.
  unknown,
}

/// Implemented by client exceptions that already know why they failed, so
/// [classifyConnectionFailure] can use their verdict instead of guessing from
/// a wrapped error it can no longer see.
abstract interface class HasFailureReason {
  ServiceFailureReason get reason;
}

/// A connection the server closed before a complete response header.
///
/// The transport counts the bytes that actually arrived on the socket, so this
/// sentence is evidence, not an inference from an [HttpException]'s wording.
/// Dart reports both a peer that closes without a byte and a peer that closes
/// halfway through the status line as `Connection closed before full header
/// was received`; the two are different answers and must not share a tone.
///
/// Zero bytes is silence ([ServiceFailureReason.unreachable], red). One byte
/// or more is an answer nobody could read ([ServiceFailureReason.invalidResponse],
/// a fault, amber): something was reached and started answering.
class ClosedBeforeHeaders implements Exception, HasFailureReason {
  const ClosedBeforeHeaders(this.receivedBytes, {this.cause});

  /// How many bytes of the answer arrived before the close.
  final int receivedBytes;

  /// The `dart:io` exception this replaces, kept for diagnostics only.
  final HttpException? cause;

  @override
  ServiceFailureReason get reason => receivedBytes == 0
      ? ServiceFailureReason.unreachable
      : ServiceFailureReason.invalidResponse;

  @override
  String toString() => receivedBytes == 0
      ? 'The server closed the connection without answering.'
      : 'The server closed the connection after '
            '$receivedBytes bytes of its answer.';
}

/// Implemented by failures that carry a sentence worth showing verbatim,
/// because [ServiceFailureReason] cannot express it.
///
/// The enum is a closed vocabulary on purpose: the UI resolves a tone, a glyph
/// and a label from it, but a handful of failures know something specific and
/// actionable that the vocabulary flattens away: *which* host a reverse proxy
/// redirected to, for instance. Those implement this so the sentence survives
/// the trip to the UI instead of collapsing into the generic copy.
abstract interface class HasFailureDetail {
  String get failureDetail;
}

/// A request that asked for JSON and got an answer that is not JSON: a web
/// page, or a body nothing can decode.
///
/// The answer to a reverse proxy's default page, a missing base path, a
/// sign-in page nobody recognised, another app on the port. Before this, a 2xx
/// was a success whatever came back, so the probe read the service as
/// answering and every list read turned the page into `[]`: "Answering" over
/// an empty library. [AnswerGuardInterceptor] raises this instead, so every
/// read gets a failure it can classify.
///
/// A **web page** is the address's fault ([ServiceFailureReason.notFound]): a
/// proxy's page or a missing base path, whatever request met it, so the probe,
/// the connection test and a library read all say `Radarr is not at this
/// address` and `A web page answered at radarr.example.com instead of
/// Radarr.` (`webPageSentence`, which names the service and so lives with the
/// registry). Any other body that does not decode is
/// [ServiceFailureReason.invalidResponse], an answer nobody can read.
///
/// It keeps what classification needs and nothing more: the status, the few
/// headers that say who answered ([relevantHeaders]), the first
/// [bodyPrefixLimit] characters of the body and the address the client was
/// built on. **None of it is ever printed**: [toString] names the status
/// only, because a body or a header can carry a session, a token or an
/// address the user did not mean to show.
class UnexpectedAnswer implements Exception, HasFailureReason {
  UnexpectedAnswer({
    this.status,
    Map<String, List<String>> headers = const {},
    String? body,
    this.host,
    this.baseUrl,
  }) : headers = {
         for (final entry in headers.entries)
           if (relevantHeaders.contains(entry.key.toLowerCase()))
             entry.key.toLowerCase(): List.unmodifiable(entry.value),
       },
       bodyPrefix = body == null || body.length <= bodyPrefixLimit
           ? body
           : body.substring(0, bodyPrefixLimit);

  /// How much of the body is kept: enough to tell a sign-in form or a
  /// Cloudflare page from an API, and bounded so a large page is not held.
  static const bodyPrefixLimit = 4096;

  /// The headers worth keeping, lower-cased: what the body is, who served it,
  /// and where it pointed.
  static const relevantHeaders = {
    'content-type',
    'server',
    'cf-ray',
    'www-authenticate',
    'location',
  };

  /// The HTTP status, or null when the body failed to decode before a
  /// response was built.
  final int? status;

  /// [relevantHeaders] only, lower-cased names.
  final Map<String, List<String>> headers;

  /// The start of the body, at most [bodyPrefixLimit] characters.
  final String? bodyPrefix;

  /// The address that answered, as the UI prints one (`radarr.example.com`,
  /// `nas.home.arpa:7878`).
  final String? host;

  /// The address the client was built on: the configured one, whose path
  /// says whether a base path could be what is missing.
  final String? baseUrl;

  String? get contentType => headers['content-type']?.firstOrNull;

  /// Whether the answer was a web page: labelled HTML, or shaped like one.
  bool get isWebPage {
    final type = contentType?.toLowerCase() ?? '';
    if (type.contains('text/html') || type.contains('xhtml')) return true;
    final start = bodyPrefix?.trimLeft().toLowerCase() ?? '';
    return start.startsWith('<!doctype html') || start.startsWith('<html');
  }

  @override
  ServiceFailureReason get reason => isWebPage
      ? ServiceFailureReason.notFound
      : ServiceFailureReason.invalidResponse;

  @override
  String toString() =>
      status == null ? 'UnexpectedAnswer' : 'UnexpectedAnswer($status)';
}

/// Implemented by a client's own exception when it wraps the failure that
/// caused it, so what that failure knew (which gateway answered, for one)
/// survives the wrapping.
abstract interface class HasFailureCause {
  Object? get failureCause;
}

/// What answered in front of a service.
enum AccessGatewayKind {
  /// A Cloudflare Access application: its login redirect, or its refusal of a
  /// request without a valid service token.
  cloudflareAccess,

  /// A sign-in page Cupola cannot complete: a redirect to an identity
  /// provider (Authelia, Authentik, an OAuth login), or a page with a
  /// password field answering where the API should be.
  signInPage,

  /// A proxy's own username and password prompt (`401` with
  /// `WWW-Authenticate: Basic`) in front of a service that does not sign in
  /// that way itself. NZBGet and Transmission do, so for them a Basic `401`
  /// stays their own refusal.
  passwordPrompt,
}

/// Something in front of the service answered in its place: the request never
/// reached the service. [ServiceFailureReason.accessGateway].
///
/// Raised by the answer guard and the redirect guard `guardedDio` installs,
/// from what the answer itself shows: where a redirect pointed, the
/// `WWW-Authenticate` and `Server` headers of a refusal, a password field in
/// a page.
///
/// [credentialsSent] is read from the request's own headers, not from
/// settings: a `CF-Access-Client-Id` for Cloudflare Access, an
/// `Authorization: Basic` the service does not use itself for a password
/// prompt. So a refusal of credentials that were sent reads differently
/// ("did not accept the service token") from a gateway nobody gave any, the
/// day a connection starts sending them, with nothing here to change.
///
/// Carries no sentence of its own ([HasFailureDetail]): its words name the
/// service, which only the surface knows, so they come from the
/// classification with this passed in (`failureHeadline(…, gateway:)`).
class AccessGatewayAnswer implements Exception, HasFailureReason {
  const AccessGatewayAnswer({
    required this.kind,
    required this.credentialsSent,
    required this.gatewayHost,
    required this.serviceHost,
  });

  final AccessGatewayKind kind;

  /// Whether the request carried the credential this gateway asks for.
  final bool credentialsSent;

  /// The host that answered for the gateway: the Access team domain
  /// (`myteam.cloudflareaccess.com`), the sign-in host, or the service's own
  /// host when the gateway answered there.
  final String gatewayHost;

  /// The configured host the request was sent to, as the UI prints one
  /// (`radarr.example.com`, `nas.home.arpa:7878`).
  final String serviceHost;

  @override
  ServiceFailureReason get reason => ServiceFailureReason.accessGateway;

  @override
  String toString() =>
      'AccessGatewayAnswer(${kind.name}, credentialsSent: $credentialsSent)';
}

/// The web page [error] met in place of the service ([UnexpectedAnswer] with
/// [UnexpectedAnswer.isWebPage]), or null; found wherever [accessGatewayOf]
/// looks.
UnexpectedAnswer? webPageAnswerOf(Object? error) {
  Object? current = unwrapFailure(error);
  for (var depth = 0; depth < 4 && current != null; depth++) {
    switch (current) {
      case final UnexpectedAnswer answer:
        return answer.isWebPage ? answer : null;
      case final ClassifiedFailure classified:
        return classified.webPage;
      case final DioException dio:
        current = dio.error;
      case final HasFailureCause wrapper:
        current = wrapper.failureCause;
      default:
        return null;
    }
  }
  return null;
}

/// The [AccessGatewayAnswer] [error] carries, or null: directly, inside the
/// [DioException] an interceptor rejected with, kept by a [ClassifiedFailure],
/// or under a client's own exception ([HasFailureCause]).
AccessGatewayAnswer? accessGatewayOf(Object? error) {
  Object? current = unwrapFailure(error);
  for (var depth = 0; depth < 4 && current != null; depth++) {
    switch (current) {
      case final AccessGatewayAnswer gateway:
        return gateway;
      case final ClassifiedFailure classified:
        return classified.gateway;
      case final DioException dio:
        current = dio.error;
      case final HasFailureCause wrapper:
        current = wrapper.failureCause;
      default:
        return null;
    }
  }
  return null;
}

/// The verbatim explanation [error] carries, or null when it has none, which
/// is the common case, and means "use the message for the reason instead".
///
/// Unwraps one [DioException] level the same way [classifyConnectionFailure]
/// does, because an interceptor's rejection reaches the caller wrapped.
String? connectionFailureDetail(Object? error) {
  Object? current = unwrapFailure(error);
  String? present(String detail) => detail.trim().isEmpty ? null : detail;
  // Through a client's own exception too ([HasFailureCause]): a refused
  // redirect inside a SABnzbd failure still knows where it was sent.
  for (var depth = 0; depth < 4 && current != null; depth++) {
    switch (current) {
      case final HasFailureDetail own:
        return present(own.failureDetail);
      case final DioException dio:
        current = dio.error;
      case final HasFailureCause wrapper:
        current = wrapper.failureCause;
      default:
        return null;
    }
  }
  return null;
}

/// Implemented by a client's own exception for a request it failed because
/// it was closed under it: the WebSocket clients (TrueNAS, Dockge) fail what
/// was in flight that way when their provider lets them go.
abstract interface class ClientClosedFailure {}

/// Whether [error] is a request that never reached anything because its own
/// client had been closed: the connection's settings changed, its provider
/// closed the client it held (`ref.onDispose(client.close)`), and something
/// still holding that client sent on it before reading the provider again.
///
/// Not the server failing, and never "did not answer": nothing was dialled.
/// The provider's rebuilt client is the one to ask, so a provider whose
/// build fails this way reads again at once (`noProviderRetry`), and the
/// shared failure states draw it as the read it is about to be
/// (`AsyncValueWidget`, `AppErrorState`).
///
/// Dio refuses a request on a closed `Dio` before sending it, as a connection
/// error with no cause and its own sentence, and a request an interceptor
/// sends again (a redirect followed, a sign-in retried) on a closed adapter
/// as a `StateError` it wraps. Both are read here, from Dio 5.9's own words,
/// and `closed_client_test.dart` holds each client to them. A client's own
/// exception is followed to the failure it wraps ([HasFailureCause]).
bool isClosedClientFailure(Object? error) {
  var current = unwrapFailure(error);
  for (var depth = 0; depth < 4 && current != null; depth++) {
    switch (current) {
      case ClientClosedFailure():
        return true;
      case DioException(
            type: DioExceptionType.connectionError,
            error: null,
            :final message,
          )
          when message != null &&
              message.contains(
                "can't establish a new connection after it "
                'was closed',
              ):
        return true;
      case DioException(error: StateError(:final message))
          when message.contains('after the adapter was closed'):
        return true;
      case DioException(error: final inner?):
        current = inner;
      case HasFailureCause(:final failureCause):
        current = failureCause;
      default:
        return false;
    }
  }
  return false;
}

/// The failure a [ParallelWaitError] stands in front of: the first of the
/// requests that failed, or the one a Riverpod [ProviderException] wraps, or
/// [error] itself.
///
/// `(a, b).wait` does not rethrow what failed: it throws a `ParallelWaitError`
/// holding every outcome, which no reason can be read from. Without this a
/// Radarr that did not answer its profile and folder reads: the add sheet's
/// load, classified as a failure nobody can attribute, and never as silence.
Object? unwrapFailure(Object? error) {
  // A provider read while in error rethrows its failure wrapped: the cause is
  // the one inside (a client provider that refused to build, say).
  if (error is ProviderException) return unwrapFailure(error.exception);
  if (error is! ParallelWaitError) return error;
  final Object? errors = error.errors;
  final Iterable<Object?> outcomes = switch (errors) {
    final Iterable<Object?> list => list,
    (final a, final b) => [a, b],
    (final a, final b, final c) => [a, b, c],
    (final a, final b, final c, final d) => [a, b, c, d],
    (final a, final b, final c, final d, final e) => [a, b, c, d, e],
    _ => const <Object?>[],
  };
  for (final outcome in outcomes) {
    if (outcome is AsyncError) return outcome.error;
  }
  return error;
}

/// Whether [error] failed on its way to or from a service: the failures the
/// classification can read, rather than an exception the app raised with a
/// sentence of its own.
bool isTransportFailure(Object? error) {
  error = unwrapFailure(error);
  return error is DioException ||
      error is SocketException ||
      error is TimeoutException ||
      error is TlsException ||
      error is HasFailureReason;
}

/// The line a failure keeps under its sentence (its *why*) for the surfaces
/// that print one (a toast's second line, a sheet's detail, a search's
/// diagnosis). **Never `toString()` of a transport failure**: that is a class
/// name and a library's paragraph.
///
/// A request that failed reads what the service itself said
/// ([failureServiceMessage]) or the classification's sentence
/// ([connectionFailureSentence]). An exception the app raised keeps its own
/// message, which is already a sentence, without the type Dart prefixes it
/// with (`Exception: `, `Bad state: `). Anything else: a `TypeError`, a
/// cast, which is internals, and reads the classification's sentence too.
String failureDiagnostic(Object? error) {
  final cause = unwrapFailure(error);
  if (isTransportFailure(cause)) {
    return failureServiceMessage(cause) ?? connectionFailureSentence(cause);
  }
  final String? own = switch (cause) {
    final StateError state => state.message,
    final Exception exception => exception.toString().replaceFirst(
      RegExp(r'^Exception:\s*'),
      '',
    ),
    _ => null,
  };
  final trimmed = own?.trim() ?? '';
  return trimmed.isEmpty ? connectionFailureSentence(cause) : trimmed;
}

/// Maps a thrown [error] onto the cause the UI should report.
///
/// [fallback] is returned only when the error carries nothing to attribute it
/// with. Socket.IO, for instance, reports connect failures as an untyped
/// string, and there `unreachable` is a better guess than `unknown`.
ServiceFailureReason classifyConnectionFailure(
  Object? error, {
  ServiceFailureReason fallback = ServiceFailureReason.unknown,
}) {
  error = unwrapFailure(error);
  if (error is HasFailureReason) return error.reason;
  if (error is DioException) return _fromDio(error, fallback);
  // A deadline wrapped around a whole request (`future.timeout(…)`) cannot say
  // whether the connection was ever made, and what it does know is that
  // nothing came back. That is "did not answer". A timeout that proves the host
  // was reached arrives as Dio's receive or send timeout, or from a client that
  // knows, and only that one is the amber [ServiceFailureReason.timeout].
  if (error is TimeoutException) return ServiceFailureReason.unreachable;
  // HandshakeException extends TlsException, so this covers both.
  if (error is TlsException) return _fromTls(error);
  if (error is SocketException) return ServiceFailureReason.unreachable;
  if (error is FormatException) return ServiceFailureReason.invalidResponse;
  return fallback;
}

/// What a failed handshake was about. BoringSSL, which Dart uses on every
/// platform, names it: `CERTIFICATE_VERIFY_FAILED` for every certificate
/// problem (an unknown issuer, an expiry, another name, a pin that does not
/// match), and `WRONG_VERSION_NUMBER` when the first bytes back are not TLS at
/// all, which is an http server's `HTTP/1.1 400` (nginx, Kestrel and so every
/// arr, Jellyfin, Node, Transmission). Anything else broke off before a
/// certificate was in question: `Connection terminated during handshake`, a
/// version or cipher the two sides do not share.
ServiceFailureReason _fromTls(TlsException error) {
  if (error is CertificateException) return ServiceFailureReason.tls;
  final said = '${error.message} ${error.osError?.message ?? ''}';
  if (said.contains('CERTIFICATE_VERIFY_FAILED')) {
    return ServiceFailureReason.tls;
  }
  if (said.contains('WRONG_VERSION_NUMBER')) {
    return ServiceFailureReason.plainHttp;
  }
  return ServiceFailureReason.noSecureConnection;
}

/// Heuristic for the services that report an auth failure inside a 200 body
/// instead of an HTTP status: SABnzbd's `{"status": false, "error": …}` and
/// Unraid's GraphQL `errors` array. Matches the wording those APIs use; a
/// miss only costs the generic message, never a wrong verdict on reachability.
bool looksUnauthorizedMessage(String message) {
  final text = message.toLowerCase();
  return text.contains('unauthor') ||
      text.contains('api key') ||
      text.contains('apikey') ||
      text.contains('forbidden') ||
      text.contains('access denied') ||
      text.contains('not logged in');
}

/// Maps a non-2xx HTTP status onto a cause, for callers that inspect the
/// status themselves instead of letting the client throw.
ServiceFailureReason reasonForStatusCode(int code) {
  if (code == 401 || code == 403) return ServiceFailureReason.unauthorized;
  if (code == 404) return ServiceFailureReason.notFound;
  if (code >= 500) return ServiceFailureReason.serverError;
  // Any 3xx that reaches here is one nothing followed: the codes
  // `allowRedirectStatus` rejects outright (300, 304, 305, 306), or a redirect
  // on a client that does not follow them. Left as `unknown` these produced
  // "Could not verify the instance", which sends the user to re-check
  // credentials that were never the problem.
  if (code >= 300 && code < 400) return ServiceFailureReason.redirected;
  return ServiceFailureReason.unknown;
}

ServiceFailureReason _fromDio(
  DioException error,
  ServiceFailureReason fallback,
) {
  // An interceptor that refused the request already reached a verdict; Dio only
  // wrapped it. Reading it here is what keeps that verdict from being re-derived
  // (wrongly) from the status code Dio happened to attach. Without this a
  // refused redirect is classified from its 3xx, which `reasonForStatusCode`
  // does not map, so every one of them landed on `unknown`.
  final wrapped = error.error;
  if (wrapped is HasFailureReason) return wrapped.reason;

  switch (error.type) {
    // The connection never completed: nothing replied at the address.
    case DioExceptionType.connectionTimeout:
      return ServiceFailureReason.unreachable;
    // The connection was made, then the exchange ran out of time: the host is
    // there, and something in it is slow or stuck.
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return ServiceFailureReason.timeout;
    case DioExceptionType.badCertificate:
      return ServiceFailureReason.tls;
    case DioExceptionType.badResponse:
      return reasonForStatusCode(error.response?.statusCode ?? 0);
    case DioExceptionType.cancel:
      return ServiceFailureReason.unknown;
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      // Dio buries the real cause here; unwrap one level.
      final inner = error.error;
      if (inner is ClosedBeforeHeaders) return inner.reason;
      if (inner is TlsException) return _fromTls(inner);
      if (inner is SocketException) return ServiceFailureReason.unreachable;
      if (inner is TimeoutException) return ServiceFailureReason.unreachable;
      // An `HttpException` alone is not proof that nothing answered: Dart
      // uses the same sentence for a peer that closed before a byte and for
      // one that closed halfway through its status line. The observed
      // transport wraps both in [ClosedBeforeHeaders] with the count it saw;
      // anything still bare here is an answer nobody could read.
      if (inner is HttpException) return ServiceFailureReason.invalidResponse;
      // Dio decodes the body after the reply arrived, so a decode failure is
      // an answer nobody could read: a proxy's HTML page, most often.
      if (inner is FormatException) return ServiceFailureReason.invalidResponse;
      return error.type == DioExceptionType.connectionError
          ? ServiceFailureReason.unreachable
          : fallback;
  }
}

/// Whether [reason] means nothing replied at all, at one address or at both:
/// the one state painted red.
///
/// The brand book's fourth rule as a function: red means `Did not answer` and
/// nothing else. A refusal, or a failure that did answer, is amber.
bool failureDidNotAnswer(ServiceFailureReason reason) =>
    reason == ServiceFailureReason.unreachable ||
    reason == ServiceFailureReason.unreachableAtBoth;

/// Whether [reason] is a **fault**: something answered, or the device
/// refused to dial, so there is one concrete thing to go and fix, rather than
/// silence.
///
/// The complement of [failureDidNotAnswer]. `unknown` is a fault too: the
/// request failed and nobody can say why, and claiming the host is silent on
/// the strength of an error nobody could read is the same lie one tone louder.
///
/// [ServiceFailureReason.sessionEnded] is not one: it is the person's step,
/// and its remedy is drawn in ink, never in the fault's amber fill. Neither is
/// [ServiceFailureReason.onlyAtHome]: a setup, read away from home.
bool failureIsFault(ServiceFailureReason reason) =>
    !failureDidNotAnswer(reason) &&
    reason != ServiceFailureReason.sessionEnded &&
    reason != ServiceFailureReason.onlyAtHome;

/// The tone a failure carries: red for [ServiceFailureReason.unreachable],
/// blue for [ServiceFailureReason.sessionEnded], neutral for
/// [ServiceFailureReason.onlyAtHome], amber for every fault. Resolve it to a
/// colour through `statusToneColor`.
StatusTone failureTone(ServiceFailureReason reason) {
  if (failureDidNotAnswer(reason)) return StatusTone.error;
  if (reason == ServiceFailureReason.sessionEnded) {
    return StateWord.signedOut.tone!;
  }
  if (reason == ServiceFailureReason.onlyAtHome) {
    return StateWord.onlyAtHome.tone!;
  }
  return StatusTone.warning;
}

/// The secret a [ServiceFailureReason.secretUnread] names: the service's own
/// word, with a sign-in's half that is secret.
String _secretNoun(String credential) =>
    credential == kRefusedSignIn ? 'password' : credential;

/// What a refusal names as the thing refused, when nothing more specific is
/// known.
///
/// `describeFailure` resolves the service's own word from the registry: `key`,
/// `token` for Plex, `sign-in` for the services that take a username and a
/// password. A surface with no service to name (a figures rail, a bare error
/// state) says `key`, which is what most of the eighteen take.
const String kRefusedCredential = 'key';

/// The word for a refused username and password, which takes a different
/// remedy (`Sign in again`) from a pasted secret (`Paste the key again`).
const String kRefusedSignIn = 'sign-in';

/// The state in a few words, for a list row, a status chip or a figure's
/// note: `Did not answer`, `Refused the key`, `Timed out`.
///
/// One vocabulary for every surface. The settings rows, the Dashboard's cells
/// and a service's header all read this, so a refused key cannot be "API key
/// rejected" on one screen and "Unreachable" on the next.
///
/// [gateway] is what answered for an [ServiceFailureReason.accessGateway]
/// ([accessGatewayOf] the failure), which names it; without one the words say
/// only that something in front asks for access. Every other reason ignores
/// it.
String failureLabel(
  ServiceFailureReason reason, {
  String credential = kRefusedCredential,
  AccessGatewayAnswer? gateway,
}) => switch (reason) {
  ServiceFailureReason.unreachable ||
  ServiceFailureReason.unreachableAtBoth => StateWord.didNotAnswer.label,
  ServiceFailureReason.unauthorized => 'Refused the $credential',
  ServiceFailureReason.addressRefused => 'Refused this address',
  ServiceFailureReason.sessionEnded => StateWord.signedOut.label,
  ServiceFailureReason.onlyAtHome => StateWord.onlyAtHome.label,
  ServiceFailureReason.secretUnread =>
    'Saved ${_secretNoun(credential)} unreadable',
  ServiceFailureReason.csrfRefused => 'Security token refused',
  ServiceFailureReason.timeout => 'Timed out',
  ServiceFailureReason.tls => 'Certificate not trusted',
  ServiceFailureReason.plainHttp => 'No https on this port',
  ServiceFailureReason.noSecureConnection => 'No secure connection',
  ServiceFailureReason.notFound => 'API not at this address',
  ServiceFailureReason.redirected => 'Redirected elsewhere',
  ServiceFailureReason.accessGateway => switch (gateway) {
    null => 'Asks for access',
    AccessGatewayAnswer(kind: AccessGatewayKind.cloudflareAccess) =>
      gateway.credentialsSent
          ? 'Service token not accepted'
          : 'Behind Cloudflare Access',
    AccessGatewayAnswer(kind: AccessGatewayKind.signInPage) =>
      'Behind a sign-in page',
    AccessGatewayAnswer(kind: AccessGatewayKind.passwordPrompt) =>
      gateway.credentialsSent
          ? 'Password not accepted'
          : 'Behind a password prompt',
  },
  ServiceFailureReason.serverError => 'Answered with an error',
  ServiceFailureReason.invalidResponse => 'Unreadable answer',
  ServiceFailureReason.insecureTransport => 'Needs https://',
  ServiceFailureReason.localNetworkBlocked => 'Local network blocked',
  ServiceFailureReason.unknown => 'Did not complete',
};

/// What happened, as the title of a fault: `Radarr did not answer`, `Radarr
/// answered but refused the key`.
///
/// [subject] is who: a service's name, or a connection's (`Radarr 4K`). This
/// is the first part of the fault sentence; the *why* is
/// [connectionFailureSentence] (or `connectionFailureMessage`, which can name
/// the service), and the remedy is [failureRemedy]. [gateway] as for
/// [failureLabel].
String failureHeadline(
  ServiceFailureReason reason, {
  required String subject,
  String credential = kRefusedCredential,
  AccessGatewayAnswer? gateway,
}) => switch (reason) {
  ServiceFailureReason.unreachable => '$subject did not answer',
  ServiceFailureReason.unreachableAtBoth =>
    '$subject did not answer at home or away',
  ServiceFailureReason.unauthorized =>
    '$subject answered but refused the $credential',
  ServiceFailureReason.addressRefused =>
    '$subject answered but refused this address',
  ServiceFailureReason.sessionEnded => 'Signed out of $subject',
  ServiceFailureReason.onlyAtHome => '$subject only works at home',
  ServiceFailureReason.secretUnread =>
    "Cupola could not read $subject's saved ${_secretNoun(credential)}",
  ServiceFailureReason.csrfRefused =>
    "$subject refused the request's security token",
  ServiceFailureReason.timeout =>
    '$subject was reached but did not reply in time',
  ServiceFailureReason.tls =>
    '$subject has a certificate Cupola does not trust',
  ServiceFailureReason.plainHttp => '$subject answered in plain http',
  ServiceFailureReason.noSecureConnection =>
    '$subject did not open a secure connection',
  ServiceFailureReason.notFound => '$subject is not at this address',
  ServiceFailureReason.redirected =>
    '$subject answered with a redirect Cupola will not follow',
  ServiceFailureReason.accessGateway => switch (gateway) {
    null => 'Something in front of $subject answered instead of it',
    AccessGatewayAnswer(kind: AccessGatewayKind.cloudflareAccess) =>
      gateway.credentialsSent
          ? 'Cloudflare Access did not accept the service token'
          : 'Cloudflare Access answered instead of $subject',
    AccessGatewayAnswer(kind: AccessGatewayKind.signInPage) =>
      'A sign-in page answered instead of $subject',
    AccessGatewayAnswer(kind: AccessGatewayKind.passwordPrompt) =>
      gateway.credentialsSent
          ? 'The proxy did not accept the password'
          : 'A password prompt answered instead of $subject',
  },
  ServiceFailureReason.serverError => '$subject answered with an error',
  ServiceFailureReason.invalidResponse =>
    '$subject answered with something Cupola cannot read',
  ServiceFailureReason.insecureTransport =>
    '$subject needs an https:// address',
  ServiceFailureReason.localNetworkBlocked =>
    'This device is keeping Cupola off the local network',
  ServiceFailureReason.unknown => 'The request to $subject did not complete',
};

/// What happened to several connections that failed the same way, as one
/// title: `Radarr, Sonarr and 6 others were reached but did not reply in
/// time`. [subjects] is them already named, more than one.
///
/// Equal faults are grouped (the brand book's fourth rule): eight services
/// behind one stuck host used to read as eight sentences, the same one eight
/// times. Null where the sentence for one cannot be said of many (a gateway's
/// answer, a secret this device would not read, Seerr's token): each of those
/// still says its own.
String? failureGroupHeadline(
  ServiceFailureReason reason, {
  required String subjects,
  String credential = kRefusedCredential,
}) => switch (reason) {
  ServiceFailureReason.unreachable => '$subjects did not answer',
  ServiceFailureReason.unreachableAtBoth =>
    '$subjects did not answer at home or away',
  ServiceFailureReason.unauthorized =>
    credential == kRefusedSignIn
        ? '$subjects answered but refused the sign-in'
        : '$subjects answered but refused their ${_pluralCredential(credential)}',
  ServiceFailureReason.addressRefused =>
    '$subjects answered but refused this address',
  ServiceFailureReason.sessionEnded => 'Signed out of $subjects',
  ServiceFailureReason.onlyAtHome => '$subjects only work at home',
  ServiceFailureReason.timeout =>
    '$subjects were reached but did not reply in time',
  ServiceFailureReason.tls =>
    '$subjects have certificates Cupola does not trust',
  ServiceFailureReason.plainHttp => '$subjects answered in plain http',
  ServiceFailureReason.noSecureConnection =>
    '$subjects did not open secure connections',
  ServiceFailureReason.notFound => '$subjects are not at their addresses',
  ServiceFailureReason.redirected =>
    '$subjects answered with redirects Cupola will not follow',
  ServiceFailureReason.serverError => '$subjects answered with an error',
  ServiceFailureReason.invalidResponse =>
    '$subjects answered with something Cupola cannot read',
  ServiceFailureReason.insecureTransport => '$subjects need https:// addresses',
  // Said of the device, not of any of them: once is enough.
  ServiceFailureReason.localNetworkBlocked =>
    'This device is keeping Cupola off the local network',
  ServiceFailureReason.unknown => 'The requests to $subjects did not complete',
  ServiceFailureReason.secretUnread ||
  ServiceFailureReason.csrfRefused ||
  ServiceFailureReason.accessGateway => null,
};

/// A refused [credential] said of many connections: `keys`, `tokens` (Plex).
String _pluralCredential(String credential) =>
    credential == 'token' ? 'tokens' : 'keys';

/// The verb that fixes this fault, when the fix is somewhere other than asking
/// again: `Paste the key again`, `Check the address`. Null when `Retry` is the
/// remedy: nothing answered, or the service answered with a failure of its
/// own that the next request may not repeat.
///
/// Each of these leads to the connection's own form, which is where the key,
/// the address, the certificate and a gateway's access live. [gateway] as for
/// [failureLabel].
String? failureRemedy(
  ServiceFailureReason reason, {
  String credential = kRefusedCredential,
  AccessGatewayAnswer? gateway,
}) => switch (reason) {
  ServiceFailureReason.unauthorized || ServiceFailureReason.secretUnread =>
    credential == kRefusedSignIn
        ? Lexicon.signInAgain
        : 'Paste the $credential again',
  ServiceFailureReason.sessionEnded => Lexicon.signInAgain,
  ServiceFailureReason.onlyAtHome => Lexicon.addAddressAway,
  ServiceFailureReason.notFound ||
  ServiceFailureReason.redirected => 'Check the address',
  ServiceFailureReason.accessGateway => switch (gateway) {
    null => 'Add access',
    AccessGatewayAnswer(kind: AccessGatewayKind.cloudflareAccess) =>
      gateway.credentialsSent ? 'Check the token' : 'Add a service token',
    AccessGatewayAnswer(kind: AccessGatewayKind.signInPage) => 'Add access',
    AccessGatewayAnswer(kind: AccessGatewayKind.passwordPrompt) =>
      gateway.credentialsSent ? 'Check the password' : 'Add the password',
  },
  ServiceFailureReason.tls => 'Check the certificate',
  ServiceFailureReason.plainHttp => 'Check the port',
  ServiceFailureReason.noSecureConnection => 'Check the address',
  ServiceFailureReason.insecureTransport => 'Change the address',
  ServiceFailureReason.unreachable ||
  ServiceFailureReason.unreachableAtBoth ||
  ServiceFailureReason.timeout ||
  ServiceFailureReason.csrfRefused ||
  ServiceFailureReason.serverError ||
  ServiceFailureReason.invalidResponse ||
  ServiceFailureReason.localNetworkBlocked ||
  // The fix lives in the service's own settings, not in the connection's form
  // a remedy opens: its sentence names the setting, and Retry follows it.
  ServiceFailureReason.addressRefused ||
  ServiceFailureReason.unknown => null,
};

/// Whether sending the same request again can still change the answer, so
/// `Retry` stays beside a remedy instead of giving way to it.
///
/// False for the causes the next request is bound to repeat: a refused key,
/// which the same key gets again, an address the device will not dial, where
/// nothing is sent at all, a gateway in front of the service, which asks
/// the same request for the same access again, and a Seerr session that
/// ended, which no request revives. Every other cause can clear while the
/// page is open: a reverse proxy that comes back, a certificate renewed at the
/// server, a service that finishes restarting. A refused **sign-in** is one of
/// them ([credential] is [kRefusedSignIn]): a ban for too many attempts runs
/// out, and a password put back at the server works again, which is why
/// qBittorrent's surfaces forget a held refusal on exactly that Retry.
bool failureRetryHelps(
  ServiceFailureReason reason, {
  String credential = kRefusedCredential,
}) => switch (reason) {
  ServiceFailureReason.unauthorized => credential == kRefusedSignIn,
  // Once the service allows the address, the same request can succeed.
  ServiceFailureReason.addressRefused => true,
  ServiceFailureReason.insecureTransport ||
  ServiceFailureReason.accessGateway ||
  ServiceFailureReason.secretUnread ||
  ServiceFailureReason.sessionEnded ||
  // Nothing was asked, and asking again from here asks nothing either.
  ServiceFailureReason.onlyAtHome ||
  // The port serves http, and it will not start serving https while the
  // page is open: the address has to change.
  ServiceFailureReason.plainHttp => false,
  ServiceFailureReason.csrfRefused ||
  ServiceFailureReason.unreachable ||
  // Retry knocks at both addresses again (`retryDashboardServices`).
  ServiceFailureReason.unreachableAtBoth ||
  ServiceFailureReason.timeout ||
  ServiceFailureReason.tls ||
  // A proxy restarting in front of the service closes handshakes too.
  ServiceFailureReason.noSecureConnection ||
  ServiceFailureReason.notFound ||
  ServiceFailureReason.redirected ||
  ServiceFailureReason.serverError ||
  ServiceFailureReason.invalidResponse ||
  ServiceFailureReason.localNetworkBlocked ||
  ServiceFailureReason.unknown => true,
};

/// A failure that has already been classified, for a place that kept the
/// verdict and lost the exception.
///
/// The Dashboard probe folds a connection into a summary; a surface that later
/// hands that summary to a failure state still owes it the right words, and
/// this carries the reason (and the sentence, when the original failure had
/// one of its own) across without inventing an exception type per client.
class ClassifiedFailure
    implements Exception, HasFailureReason, HasFailureDetail {
  const ClassifiedFailure(
    this.reason, {
    this.detail,
    this.gateway,
    this.webPage,
  });

  /// Classifies [error] once and keeps what the words need.
  factory ClassifiedFailure.of(Object? error) => error is ClassifiedFailure
      ? error
      : ClassifiedFailure(
          classifyConnectionFailure(error),
          detail: connectionFailureDetail(error),
          gateway: accessGatewayOf(error),
          webPage: webPageAnswerOf(error),
        );

  @override
  final ServiceFailureReason reason;

  /// The failure's own sentence, when it carried one ([HasFailureDetail]).
  final String? detail;

  /// What answered in front of the service, for an
  /// [ServiceFailureReason.accessGateway]: the words name it.
  final AccessGatewayAnswer? gateway;

  /// The web page that answered in the service's place, when one did: its
  /// sentence names where.
  final UnexpectedAnswer? webPage;

  @override
  String get failureDetail => detail ?? '';

  @override
  String toString() => 'ClassifiedFailure(${reason.name})';
}

/// What the service itself said when it answered with a failure, verbatim:
/// the line a fault keeps under *Why?*, or null when it said nothing a
/// person can read.
///
/// Read from the body of a reply Dio kept: an object's `message` or `error`
/// (the \*arrs, Seerr, Nginx Proxy Manager), or the `errorMessage` of each
/// entry in a validation list (the \*arrs' 400s: *This movie has already been
/// added*). A body that is a bare string is left alone on purpose: it is as
/// often a reverse proxy's HTML page as it is a sentence.
String? failureServiceMessage(Object? error) {
  error = unwrapFailure(error);
  if (error is! DioException) return null;
  final data = error.response?.data;
  String? text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (data is Map) {
    return text(data['message']) ??
        text(data['error']) ??
        text(data['errorMessage']);
  }
  if (data is List) {
    final messages = [
      for (final entry in data)
        if (entry is Map)
          ?text(entry['errorMessage']) ?? text(entry['message']),
    ];
    return messages.isEmpty ? null : messages.toSet().join(' ');
  }
  return null;
}

/// A failed read in one plain sentence, for a surface that has no service to
/// name: `AppErrorState`, which only knows a display string.
///
/// **Never the exception.** `error.toString()` is a class name and a library's
/// message ("DioException [connection error]: … This indicates an error which
/// most likely cannot be solved by the library."), and it was the line under
/// every failed load in the app. The sentence comes from the classification
/// instead, in the words `connectionFailureMessage` uses where it can name the
/// service; a failure that carries its own verbatim sentence
/// ([HasFailureDetail]) keeps it.
///
/// [remedyBeside] is for a surface that draws the remedy as a button right
/// under the sentence: there "Check them in Settings." would repeat the
/// button in words, so the sentence stops at the fact.
///
/// [subject] names the service where a sentence names one (a gateway's: `Radarr
/// is behind Cloudflare Access.`); without it the sentence names the address.
String connectionFailureSentence(
  Object? error, {
  bool remedyBeside = false,
  String? subject,
}) {
  final detail = connectionFailureDetail(error);
  if (detail != null && detail.trim().isNotEmpty) return detail;
  final page = webPageAnswerOf(error);
  if (page != null) {
    final where = page.host == null || page.host!.isEmpty
        ? ''
        : ' at ${UrlUtils.hostInProse(page.host!)}';
    return 'A web page answered$where instead of ${subject ?? 'the service'}.';
  }
  return switch (classifyConnectionFailure(error)) {
    ServiceFailureReason.unreachable =>
      'Nothing answered at the saved address. Check that the server is '
          'running and reachable from this device.',
    ServiceFailureReason.unreachableAtBoth =>
      'Nothing answered at either saved address: the server may be down, '
          'or this device may have no network.',
    // Said after a headline that already names the failure, so each adds what
    // to do rather than restating it.
    ServiceFailureReason.timeout => 'It may be busy. Retry in a moment.',
    ServiceFailureReason.tls =>
      'If its certificate changed, trust it again in its settings.',
    ServiceFailureReason.plainHttp =>
      'Its address names a port that serves http. Use the one that serves '
          'https.',
    ServiceFailureReason.noSecureConnection =>
      'The secure connection broke off before a certificate arrived. Check '
          'that its address serves https.',
    ServiceFailureReason.unauthorized =>
      remedyBeside
          ? 'The server answered and refused the saved credentials.'
          : 'The server answered and refused the saved credentials. Check '
                'them in Settings.',
    ServiceFailureReason.addressRefused =>
      'If the password is right, allow this address in its settings.',
    ServiceFailureReason.sessionEnded =>
      'Sign in again to keep asking for movies and series.',
    ServiceFailureReason.onlyAtHome =>
      '${subject ?? 'It'} has no address away, so Cupola reaches it only on '
          'your home Wi-Fi.',
    ServiceFailureReason.secretUnread =>
      "${secureStoreName()} didn't hand it over.",
    ServiceFailureReason.csrfRefused => 'Nothing changed. Retry in a moment.',
    ServiceFailureReason.notFound =>
      'Something answered, but the API is not at this address.',
    ServiceFailureReason.redirected =>
      'The server answered with a redirect Cupola will not follow.',
    ServiceFailureReason.accessGateway => accessGatewaySentence(
      accessGatewayOf(error),
      subject: subject,
    ),
    ServiceFailureReason.serverError =>
      'The server answered with an error of its own. Its logs will say why.',
    ServiceFailureReason.invalidResponse =>
      'Something answered, but not with anything Cupola can read. A reverse '
          'proxy page at this address is the usual cause.',
    ServiceFailureReason.insecureTransport =>
      'The address starts with http://, so Cupola did not send the key over '
          'it. Change it to https://.',
    ServiceFailureReason.localNetworkBlocked =>
      'This device is blocking Cupola from reaching the local network.',
    ServiceFailureReason.unknown => 'The request did not complete.',
  };
}

/// Why a gateway answered instead of the service, and what it wants: the
/// sentence under [failureHeadline] for an [ServiceFailureReason.accessGateway].
///
/// [subject] names the service (`Radarr`); without one the sentence names the
/// address the request went to, or says "the service". The host a refused
/// service token wants a policy on is the configured one, never the Access
/// team's.
String accessGatewaySentence(AccessGatewayAnswer? gateway, {String? subject}) {
  final host = UrlUtils.hostInProse(gateway?.serviceHost ?? '');
  final who = subject ?? (host.isEmpty ? 'the service' : host);
  // A name or an address opens the sentence as it is spelled; only the
  // fallback takes a capital.
  final opening = who == 'the service' ? 'The service' : who;
  return switch (gateway) {
    null => 'Something in front of $who answered in its place.',
    AccessGatewayAnswer(kind: AccessGatewayKind.cloudflareAccess) =>
      gateway.credentialsSent
          ? 'Add a Service Auth policy for it on '
                '${host.isEmpty ? 'the application' : host}, or make a new '
                'token if it expired.'
          : '$opening is behind Cloudflare Access. Cupola needs a service '
                'token to reach it.',
    AccessGatewayAnswer(kind: AccessGatewayKind.signInPage) =>
      'Something in front of $who asks for a sign-in that Cupola cannot '
          'complete.',
    AccessGatewayAnswer(kind: AccessGatewayKind.passwordPrompt) =>
      gateway.credentialsSent
          ? 'Something in front of $who asked for a username and password, '
                'and refused the ones Cupola sent.'
          : 'Something in front of $who asks for a username and password.',
  };
}
