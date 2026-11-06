import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

AudienceConnection _seerr(SeerrGrant? grant) =>
    (service: ServiceKey.seerr, seerr: grant);

AudienceConnection _service(ServiceKey service) =>
    (service: service, seerr: null);

/// Anna, the household default: REQUEST and nothing else.
final _anna = _seerr(
  SeerrGrant.account(permissions: SeerrPermission.request.value),
);

/// A requester who may also see everyone's requests and choose where they go.
final _luca = _seerr(
  SeerrGrant.account(
    permissions:
        SeerrPermission.request.value |
        SeerrPermission.requestView.value |
        SeerrPermission.requestAdvanced.value,
  ),
);

final _manager = _seerr(
  SeerrGrant.account(
    permissions:
        SeerrPermission.request.value | SeerrPermission.manageRequests.value,
  ),
);

void main() {
  group('who the app is for', () {
    final rows = <(String, List<AudienceConnection>, Audience)>[
      ('nothing set up', [], Audience.operator),
      ('a requester account alone', [_anna], Audience.requester),
      ('two requester accounts', [_anna, _luca], Audience.requester),
      (
        'a requester with the players they watch with',
        [_anna, _service(ServiceKey.jellyfin), _service(ServiceKey.plex)],
        Audience.requester,
      ),
      (
        'the Seerr API key',
        [_seerr(const SeerrGrant.apiKey())],
        Audience.operator,
      ),
      (
        'a Seerr connection with no grant reads as the key',
        [_seerr(null)],
        Audience.operator,
      ),
      ('an account that manages requests', [_manager], Audience.operator),
      (
        'a requester beside a key',
        [_anna, _seerr(const SeerrGrant.apiKey())],
        Audience.operator,
      ),
      ('a requester beside a manager', [_anna, _manager], Audience.operator),
      (
        'players without Seerr',
        [_service(ServiceKey.jellyfin), _service(ServiceKey.plex)],
        Audience.operator,
      ),
    ];
    for (final (name, connections, audience) in rows) {
      test(name, () => expect(audienceOf(connections), audience));
    }
  });

  test('any other service makes the operator', () {
    const players = {
      ServiceKey.seerr,
      ServiceKey.jellyfin,
      ServiceKey.plex,
      ServiceKey.emby,
    };
    for (final service in ServiceKey.values) {
      if (players.contains(service)) continue;
      expect(
        audienceOf([_anna, _service(service)]),
        Audience.operator,
        reason: service.name,
      );
      // In either order: the first connection does not decide.
      expect(
        audienceOf([_service(service), _anna]),
        Audience.operator,
        reason: service.name,
      );
    }
  });

  test('a requester who can see more is still a requester', () {
    // REQUEST_VIEW and REQUEST_ADVANCED do not make a manager: approving does.
    expect(audienceOf([_luca]), Audience.requester);
    expect(
      audienceOf([
        _seerr(
          SeerrGrant.account(permissions: SeerrPermission.manageUsers.value),
        ),
      ]),
      Audience.requester,
    );
  });

  test('ADMIN on an account makes the operator', () {
    expect(
      audienceOf([
        _seerr(SeerrGrant.account(permissions: SeerrPermission.admin.value)),
      ]),
      Audience.operator,
    );
  });
}
