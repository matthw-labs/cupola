import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('Password is offered only where a proxy password can travel', () {
    const signInWithAuthorization = {
      ServiceKey.nginxProxyManager,
      ServiceKey.nzbget,
      ServiceKey.transmission,
      ServiceKey.tracearr,
    };

    for (final service in ServiceKey.values) {
      test(service.title, () {
        final kinds = accessKindsFor(service);
        if (signInWithAuthorization.contains(service)) {
          expect(kinds, [
            AccessKind.none,
            AccessKind.cloudflare,
            AccessKind.custom,
          ]);
          expect(service.proxyPasswordUnavailable, isNotNull);
        } else {
          expect(kinds, AccessKind.values);
          expect(service.proxyPasswordUnavailable, isNull);
        }
      });
    }

    test('and says why, in one line', () {
      expect(
        ServiceKey.nginxProxyManager.proxyPasswordUnavailable,
        'Nginx Proxy Manager signs in with its own Authorization header, so '
        "a proxy password cannot travel with it.",
      );
      expect(
        ServiceKey.nzbget.proxyPasswordUnavailable,
        "NZBGet signs in with its own Authorization header, so a proxy "
        "password cannot travel with it.",
      );
      expect(
        ServiceKey.transmission.proxyPasswordUnavailable,
        "Transmission signs in with its own Authorization header, so a proxy "
        "password cannot travel with it.",
      );
    });
  });

  group('a custom header named like the service\'s own credential', () {
    test('is offered a move into the credential field', () {
      expect(
        duplicatesCredentialHeader(ServiceKey.radarr, 'x-api-key'),
        isTrue,
      );
      expect(customHeaderNameProblem(ServiceKey.radarr, 'X-Api-Key'), isNull);
      expect(
        credentialHeaderClash(ServiceKey.radarr),
        "Cupola already sends Radarr's key. Move it to the API key field?",
      );
      expect(
        credentialHeaderClash(ServiceKey.plex),
        "Cupola already sends Plex's token. Move it to the Plex token field?",
      );
      expect(
        duplicatesCredentialHeader(ServiceKey.jellyfin, 'X-Emby-Token'),
        isTrue,
      );
    });

    test('is not a clash on a service that does not send it', () {
      expect(
        duplicatesCredentialHeader(ServiceKey.sabnzbd, 'X-Api-Key'),
        isFalse,
      );
      expect(customHeaderNameProblem(ServiceKey.sabnzbd, 'X-Api-Key'), isNull);
    });
  });

  group('a custom header name', () {
    test('never one the transport or the protocol owns', () {
      for (final name in [
        'Host',
        'Content-Length',
        'content-type',
        'Accept',
        'Connection',
        'Transfer-Encoding',
        'Upgrade',
        'Cookie',
        'Sec-WebSocket-Key',
        'sec-websocket-protocol',
      ]) {
        expect(
          customHeaderNameProblem(ServiceKey.radarr, name),
          'Cupola sets this header itself',
          reason: name,
        );
      }
    });

    test('never one the service sets itself', () {
      expect(
        customHeaderNameProblem(ServiceKey.nzbget, 'Authorization'),
        'Cupola sets this header itself',
      );
      expect(
        customHeaderNameProblem(
          ServiceKey.transmission,
          'X-Transmission-Session-Id',
        ),
        'Cupola sets this header itself',
      );
      expect(
        customHeaderNameProblem(ServiceKey.plex, 'X-Plex-Client-Identifier'),
        'Cupola sets this header itself',
      );
      // Free where the service does not sign in with it: Jellyfin moves its
      // token to X-Emby-Token.
      expect(
        customHeaderNameProblem(ServiceKey.radarr, 'Authorization'),
        isNull,
      );
      expect(
        customHeaderNameProblem(ServiceKey.jellyfin, 'Authorization'),
        isNull,
      );
    });

    test('is an RFC 9110 token', () {
      expect(customHeaderNameProblem(ServiceKey.radarr, ''), 'Add a name');
      for (final name in ['X Proxy', 'X:Proxy', 'X-Pröxy', 'X(1)', 'a"b']) {
        expect(
          customHeaderNameProblem(ServiceKey.radarr, name),
          'Use letters, digits and dashes',
          reason: name,
        );
      }
      for (final name in ['X-Proxy-Key', "x!#\$%&'*+.^_`|~1"]) {
        expect(customHeaderNameProblem(ServiceKey.radarr, name), isNull);
      }
    });

    test('appears once', () {
      expect(
        customHeaderNameProblem(
          ServiceKey.radarr,
          'x-proxy',
          earlier: ['X-Proxy'],
        ),
        'This header is already in the list',
      );
    });
  });

  test('a value stays on one line', () {
    expect(customHeaderValueProblem(''), 'Add a value');
    expect(
      customHeaderValueProblem('a\r\nInjected: 1'),
      'Keep the value on one line',
    );
    expect(customHeaderValueProblem('a\nb'), 'Keep the value on one line');
    expect(customHeaderValueProblem('Bearer abc'), isNull);
  });

  test('the headers stay under 8 KB in all', () {
    expect(
      exceedsAccessHeadersLimit([(name: 'X-A', value: 'v' * 8000)]),
      isFalse,
    );
    expect(
      exceedsAccessHeadersLimit([
        (name: 'X-A', value: 'v' * 5000),
        (name: 'X-B', value: 'v' * 5000),
      ]),
      isTrue,
    );
  });

  test('a proxy username', () {
    expect(proxyUsernameProblem(''), 'Add the username');
    expect(proxyUsernameProblem('a:b'), 'A username cannot contain a colon');
    expect(proxyUsernameProblem('matt'), isNull);
  });

  test('a whole access is valid only without a clash', () {
    expect(accessIsValid(ServiceKey.radarr, const NoAccess()), isTrue);
    expect(
      accessIsValid(
        ServiceKey.radarr,
        const CloudflareServiceToken(clientId: 'a', clientSecret: ''),
      ),
      isFalse,
    );
    expect(
      accessIsValid(
        ServiceKey.nzbget,
        const ProxyPassword(username: 'u', password: 'p'),
      ),
      isFalse,
    );
    expect(
      accessIsValid(
        ServiceKey.radarr,
        const CustomHeaders([(name: 'X-Api-Key', value: 'k')]),
      ),
      isFalse,
    );
    expect(
      accessIsValid(
        ServiceKey.radarr,
        const CustomHeaders([(name: 'X-Proxy', value: 'k')]),
      ),
      isTrue,
    );
  });
}
