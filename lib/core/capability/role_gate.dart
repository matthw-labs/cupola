import 'package:flutter/foundation.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_copy.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What one gated control draws: live, dimmed with its reason, or nothing.
sealed class GateVerdict {
  const GateVerdict();

  /// Whether the control acts when pressed.
  bool get acts => this is Live;

  /// Whether the control is drawn at all.
  bool get isDrawn => this is! Absent;

  /// Why a dimmed control does not act; null otherwise.
  String? get reason => null;
}

/// Drawn, and it acts.
final class Live extends GateVerdict {
  const Live();

  @override
  bool operator ==(Object other) => other is Live;

  @override
  int get hashCode => (Live).hashCode;

  @override
  String toString() => 'GateVerdict.live';
}

/// Drawn, dimmed but still tappable, keeping its target, and saying
/// [reason] when pressed and to a screen reader.
final class Dimmed extends GateVerdict {
  const Dimmed(this.reason);

  @override
  final String reason;

  @override
  bool operator ==(Object other) => other is Dimmed && other.reason == reason;

  @override
  int get hashCode => Object.hash(Dimmed, reason);

  @override
  String toString() => 'GateVerdict.dimmed($reason)';
}

/// Not drawn: the control is not part of this person's app.
final class Absent extends GateVerdict {
  const Absent();

  @override
  bool operator ==(Object other) => other is Absent;

  @override
  int get hashCode => (Absent).hashCode;

  @override
  String toString() => 'GateVerdict.absent';
}

/// How a failure speaks on a shared surface.
enum FaultVoice {
  /// The whole classification: the cause, the service, the remedy it names.
  full,

  /// One line with the time the content dates from, and Retry. The
  /// requester never reads a key, a certificate or a status code.
  brief,
}

/// The one object a shared surface reads to decide what to draw.
///
/// It puts together who the app is for ([audience]) and what the Seerr
/// connection the surface shows may do ([grant], with the [server] it is on).
/// Every choice between live, dimmed and absent is made here, by one rule:
///
/// | audience, control          | the account may | it may not             |
/// |----------------------------|-----------------|------------------------|
/// | operator, any              | [Live]          | [Dimmed], never hidden |
/// | requester, an operator's   | [Absent]        | [Absent]               |
/// | requester, their own       | [Live]          | [Dimmed] with a reason |
///
/// The requester's own controls are asking and cancelling; every other one
/// is the operator's, and has no place in the requester's app.
///
/// Presentation, not security: Seerr enforces every permission itself. The
/// gate keeps the app from promising what the server would refuse.
///
/// With the API key everything is [Live], names and faults in full: exactly
/// the app the operator has today.
@immutable
final class RoleGate {
  const RoleGate({required this.audience, this.grant, this.server});

  /// The operator's gate on a surface that reads no Seerr.
  const RoleGate.operator() : this(audience: Audience.operator);

  final Audience audience;

  /// What the surface's Seerr connection may do. Null: the surface reads no
  /// Seerr, and only [audience] decides.
  final SeerrGrant? grant;

  /// The server that connection is on, for its name and its 4K servers.
  final SeerrServerFacts? server;

  bool get _operator => audience == Audience.operator;

  String get _serverTitle => server?.title ?? 'Seerr';

  /// A control that does [ability]: Manage, Approve and Decline, the
  /// destination pickers, Remove, Clear data.
  ///
  /// For the requester an operator's ability is [Absent] whatever the account
  /// may do: a requester with REQUEST_ADVANCED still sees no picker, which
  /// would read "Radarr 4K". The requester's own abilities are [Live] or
  /// [Dimmed] with a reason.
  GateVerdict operatorAction(SeerrAbility ability, {SeerrMediaKind? kind}) {
    final grant = this.grant;
    if (!_operator && ability.belongsToOperator) return const Absent();
    if (grant == null) return _operator ? const Live() : const Absent();
    if (grant.may(ability, kind: kind)) return const Live();
    return Dimmed(_cannot(ability, kind));
  }

  /// Request, for a title of [kind]: in 4K when [is4k], against the account's
  /// [quota] when it was read.
  ///
  /// A 4K request the gate does not [offers4k] is [Absent] in either
  /// audience: 4K is an option of the request, and an option the server or the
  /// account cannot take is not drawn. A quota the server says is reached
  /// dims Request with the limit, a manager's included: going past it is a
  /// choice the request sheet makes, not this verdict.
  GateVerdict requestAction(
    SeerrMediaKind kind, {
    bool is4k = false,
    SeerrQuota? quota,
  }) {
    final grant = this.grant;
    if (grant == null) return _operator ? const Live() : const Absent();
    if (is4k && !offers4k(kind)) return const Absent();
    final ability = is4k ? SeerrAbility.request4k : SeerrAbility.request;
    if (!grant.may(ability, kind: kind)) return Dimmed(_cannot(ability, kind));

    final limit = quota?.of(kind);
    if (limit != null && limit.restricted) {
      return Dimmed(
        _operator
            ? RoleGateCopy.accountQuotaReached(
                limit,
                kind,
                server: _serverTitle,
              )
            : RoleGateCopy.youQuotaReached(limit, kind),
      );
    }
    return const Live();
  }

  /// Cancel (or, with MANAGE_REQUESTS, delete) one request: [own] when the
  /// connection's account made it, [waitingForApproval] while it is still
  /// pending.
  ///
  /// The requester is offered it only on an own request that still waits;
  /// anywhere else it is not part of their app. The operator sees it dimmed
  /// with the reason.
  GateVerdict cancelAction({
    required bool own,
    required bool waitingForApproval,
  }) {
    final grant = this.grant;
    if (grant == null) return _operator ? const Live() : const Absent();
    if (grant.mayCancelRequest(
      own: own,
      waitingForApproval: waitingForApproval,
    )) {
      return const Live();
    }
    if (!_operator) return const Absent();
    return Dimmed(
      own
          ? RoleGateCopy.notWaitingForApproval
          : RoleGateCopy.accountCannotCancelOthers(server: _serverTitle),
    );
  }

  /// Resolve on one issue, [own] when this connection's account reported it.
  ///
  /// Not part of the requester's app. The operator's account sees it dimmed
  /// with the reason where the server would refuse it.
  GateVerdict resolveIssueAction({required bool own}) {
    final grant = this.grant;
    if (!_operator) return const Absent();
    if (grant == null || grant.mayResolveIssue(own: own)) return const Live();
    return Dimmed(_cannot(SeerrAbility.manageIssues, null));
  }

  /// Whether the request sheet offers 4K for [kind]: the account may ask for
  /// it **and** the server has a default 4K server for it.
  bool offers4k(SeerrMediaKind kind) {
    final grant = this.grant;
    final server = this.server;
    if (grant == null || server == null) return false;
    return grant.may(SeerrAbility.request4k, kind: kind) && server.has4k(kind);
  }

  /// Whether a surface shows who made a request. Never for the requester; for
  /// the operator, when the connection sees everyone's requests.
  bool get showsRequesterNames =>
      _operator && (grant?.may(SeerrAbility.seeEveryonesRequests) ?? true);

  /// Activity, the Stack, the service rooms and the command deck.
  bool get showsControlRoom => _operator;

  /// Whether a surface may name [service]. The requester reads only the
  /// players they watch with; Seerr itself they know by its own title, at
  /// sign-in and in the account, and nowhere else.
  bool namesService(ServiceKey service) {
    if (_operator) return true;
    return switch (service) {
      ServiceKey.jellyfin || ServiceKey.plex || ServiceKey.emby => true,
      ServiceKey.seerr ||
      ServiceKey.radarr ||
      ServiceKey.sonarr ||
      ServiceKey.lidarr ||
      ServiceKey.qbittorrent ||
      ServiceKey.transmission ||
      ServiceKey.bazarr ||
      ServiceKey.truenas ||
      ServiceKey.dockge ||
      ServiceKey.prowlarr ||
      ServiceKey.readarr ||
      ServiceKey.sabnzbd ||
      ServiceKey.nzbget ||
      ServiceKey.unraid ||
      ServiceKey.nginxProxyManager ||
      ServiceKey.tracearr => false,
    };
  }

  /// How a failure on this surface speaks.
  FaultVoice get faultVoice => _operator ? FaultVoice.full : FaultVoice.brief;

  String _cannot(SeerrAbility ability, SeerrMediaKind? kind) => _operator
      ? RoleGateCopy.accountCannot(ability, server: _serverTitle, kind: kind)
      : RoleGateCopy.youCannot(ability, kind: kind);

  @override
  bool operator ==(Object other) =>
      other is RoleGate &&
      other.audience == audience &&
      other.grant == grant &&
      other.server == server;

  @override
  int get hashCode => Object.hash(audience, grant, server);

  @override
  String toString() => 'RoleGate(${audience.name}, $grant, $server)';
}
