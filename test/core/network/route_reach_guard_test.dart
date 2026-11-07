import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/app_sources.dart';

/// Everything that reaches a server goes where the connection's route is:
/// the eighth obligation of a client, beside ADR-6's five, the access
/// headers' sixth and Seerr's seventh.
///
/// A connection is saved and known by its address at home
/// (`ServiceInstance.url`, `.access`), and may be reached away from home at a
/// second one, with the access its own gateway asks for and the certificate
/// trusted at its own origin. Which of the two a request goes to is the
/// route's (`reachOf`), read through `watchTransport`,
/// `connectionReachProvider` or `connectionRouteProvider`. A client, a
/// request, a picture's address or a link to a web page built from the
/// saved address instead works at home and fails away from home, where the
/// regression would be found: a source scan, because it is one argument in a
/// diff.
///
/// Read for every file in `lib/` but the four that define the address, store
/// it and turn it into a reach: each read of the saved address (a
/// connection's `.url` or `.access`, `pinForUrl(` of an address,
/// `urlFor(`, a legacy `radarrUrl`-style projection) is counted per file and
/// shape. Every count must be listed in [_exceptions] with the reason the
/// read names the connection rather than reaching it (identity, a sentence
/// that shows it, the form that edits it, the test of an address just
/// typed), and every entry must still match. A new reader either follows the
/// route or adds its line here, with its reason.
void main() {
  final reads = <String, int>{};
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    if (file.path.startsWith('lib/core/generated/')) continue;
    if (isServerStandIn(file.path)) continue;
    if (_whereTheAddressLives.contains(file.path)) continue;
    final code = _withoutComments(file.readAsStringSync());
    for (final (:name, :pattern) in _reads) {
      final count = pattern.allMatches(code).length;
      if (count > 0) reads['${file.path}  $name'] = count;
    }
  }

  test('there are reads to check', () {
    // A scanner that silently found nothing would pass the checks below.
    expect(reads.values.fold<int>(0, (a, b) => a + b), greaterThan(40));
  });

  test('every read of the saved address is one that names the connection', () {
    final unlisted = [
      for (final MapEntry(key: site, value: count) in reads.entries)
        if (_exceptions[site]?.count != count)
          '$site: $count read(s), ${_exceptions[site]?.count ?? 0} listed',
    ];
    expect(
      unlisted,
      isEmpty,
      reason:
          'A read of the saved address. If it builds a client, a request, a '
          'picture or a link, take the route\'s instead (watchTransport, '
          'connectionReachProvider, connectionRouteProvider or reachOf); if '
          'it only names the connection, list it in _exceptions with why.',
    );
  });

  test('every exception still matches a read', () {
    expect(_exceptions.keys.where((site) => !reads.containsKey(site)), isEmpty);
  });

  test('every client built off a transport is told when it may not ask', () {
    // Away from home, a connection with no address away is not asked: the
    // transport says so (`onlyAtHome`), and the client it builds refuses
    // every request without dialling (`OnlyAtHomeRefusal`). A client built
    // without it sends its request to the address at home and waits out a
    // timeout to learn what the route already said, then paints it red.
    final untold = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path == 'lib/features/settings/data/settings_provider.dart') {
        continue;
      }
      if (_transportReaders.containsKey(file.path)) continue;
      final code = _withoutComments(file.readAsStringSync());
      // A client is built off a transport by `watchTransport` itself or by a
      // `ConnectionProviders.transport` pair, which calls it for its caller.
      final transports = RegExp(
        r'\b(?:watchTransport|ConnectionProviders<[^>]+>\.transport)\(',
      ).allMatches(code).length;
      final told = RegExp(
        r'\.onlyAtHomeOf\(|\.onlyAtHome\b',
      ).allMatches(code).length;
      if (told < transports) {
        untold.add('${file.path}: $transports transport(s), $told told');
      }
      // A MediaBrowser server is built off a transport by the one set of
      // providers they share, which reads it for each service's `create`: the
      // transport is counted there, and the service that hands its client
      // over is the one to tell it.
      final sets = RegExp(
        r'\bMediaBrowserProviders<\w+>\(',
      ).allMatches(code).length;
      if (told < sets) {
        untold.add('${file.path}: $sets provider set(s), $told told');
      }
    }
    expect(
      untold,
      isEmpty,
      reason:
          'Pass onlyAtHome: transport.onlyAtHomeOf(service) to the client '
          'built off the transport.',
    );
  });
}

/// The files that read a transport without building a client from it, and
/// why.
const _transportReaders = <String, String>{
  'lib/features/jellyfin/presentation/media_browser_providers.dart':
      'Builds no client: every server of the family hands its own `create` to '
      'the set, which this guard reads where the set is built (a file that '
      'builds one is held to telling its client).',
  'lib/features/settings/data/connection_providers.dart':
      'Builds no client: it hands the transport to the `create` of each '
      '`ConnectionProviders.transport`, which this guard reads where the '
      'client is built.',
  'lib/core/status/read_clock.dart':
      'Keys a read\'s clock by the connection the request goes to.',
  'lib/features/qbittorrent/presentation/qbittorrent_provider.dart':
      'Reads the connection\'s one client, qbittorrentClientForProvider, '
      'which is told.',
};

/// Where the address is defined, stored and turned into a reach: reading it
/// is their job.
const _whereTheAddressLives = {
  'lib/features/settings/domain/service_instance.dart',
  'lib/features/settings/domain/settings_model.dart',
  'lib/features/settings/domain/connection_reach.dart',
  'lib/features/settings/data/settings_service.dart',
};

/// The names a connection goes by in `lib/`, as a bare receiver: a field of
/// something else (`source.connection.url`, a record already on the route)
/// is not one.
const _connectionNames =
    'instance|connection|server|sibling|seerr|prowlarr|saved|named|primary|'
    'live|lens|candidateInstance|tested|prior|written|_connection|_target|'
    'target';

/// The shapes of a read of the saved address.
final _reads = <({String name, RegExp pattern})>[
  (
    name: '.url',
    pattern: RegExp('(?<![\\w.])(?:$_connectionNames)[?!]?\\.url\\b'),
  ),
  (
    name: '.access',
    pattern: RegExp('(?<![\\w.])(?:$_connectionNames)[?!]?\\.access\\b'),
  ),
  // A connection looked up and read in one breath.
  (
    name: 'lookup.url',
    pattern: RegExp(
      r'(?:instanceById|primaryOf|activeInstanceProvider)\([^()]*\)\)?'
      r'[?!]?\.(?:url|access)\b',
    ),
  ),
  (name: 'pinForUrl(', pattern: RegExp(r'\bpinForUrl\(')),
  (name: 'urlFor(', pattern: RegExp(r'\burlFor\(')),
  // `settings.urlFor(ServiceKey.radarr)` and its kin: the first connection's saved address.
  // A field of another class that happens to share the name is its own.
  (
    name: 'projection',
    pattern: RegExp(
      r'(?<!\bthis)\.(?:seerr|radarr|sonarr|lidarr|readarr|prowlarr|bazarr|'
      r'qbittorrent|transmission|sabnzbd|nzbget|npm|truenas|dockge|unraid|'
      r'jellyfin|plex)Url\b',
    ),
  ),
];

/// `file  shape` → how many reads of that shape the file makes, and why each
/// names the connection rather than reaching it.
const _exceptions = <String, ({int count, String reason})>{
  // === Identity: the connection as it is saved and known ===================
  'lib/core/capability/capability_scope.dart  .url': (
    count: 1,
    reason:
        'A refusal learned for a credential is forgotten when the connection '
        'is edited: keyed on what it is saved as, not on where it answers.',
  ),
  'lib/core/capability/connection_capability.dart  .url': (
    count: 2,
    reason:
        'The stamp a credential\'s grant is asked again on, with its pin and '
        'access below. The probe itself reads the connection\'s own client, '
        'which follows the route and asks again when it moves.',
  ),
  'lib/core/capability/connection_capability.dart  pinForUrl(': (
    count: 1,
    reason: 'The same stamp: the certificate the connection is saved with.',
  ),
  'lib/core/capability/connection_capability.dart  .access': (
    count: 1,
    reason: 'The same stamp: the access the connection is saved with.',
  ),
  'lib/features/discover/data/seerr_accounts.dart  .url': (
    count: 1,
    reason:
        'Saving a sign-in writes the address the connection is known by, '
        'whichever of its two the sign-in went to.',
  ),
  'lib/features/discover/data/seerr_accounts.dart  .access': (
    count: 1,
    reason: 'The same save: the access at home, as the form holds it.',
  ),
  'lib/features/discover/data/seerr_auth_service.dart  .url': (
    count: 2,
    reason:
        'The address a session belongs to, the saved one; and the address '
        'at home a client without a reach goes to (a test, an address just '
        'typed).',
  ),
  'lib/features/discover/data/seerr_session.dart  .url': (
    count: 1,
    reason:
        'seerrClientFor without a reach: the address at home with no pin, '
        'for a test and an address just typed. Every caller in lib/ passes '
        'one (seerr_client_guard_test).',
  ),
  'lib/features/discover/data/seerr_session.dart  .access': (
    count: 1,
    reason: 'The same default: the access at home.',
  ),
  'lib/features/discover/domain/seerr_arr_server.dart  .url': (
    count: 1,
    reason:
        'Compared with the address Seerr reports for its server: whether it '
        'is this connection, by the address it is saved with.',
  ),
  'lib/features/discover/domain/seerr_invite.dart  .url': (
    count: 6,
    reason:
        'An invite names the addresses it hands over, finds the Seerr already '
        'here at them and fills what that one lacks; the household member\'s '
        'app reaches them, never this one.',
  ),
  'lib/features/discover/domain/seerr_invite.dart  .access': (
    count: 3,
    reason:
        'Whether an address asks for a token, said beside the link; shown in '
        'person, the access is handed over, or fills the Seerr already here. '
        'Nothing here reaches the server.',
  ),
  'lib/features/discover/domain/seerr_invite.dart  pinForUrl(': (
    count: 1,
    reason: 'The certificate an invite vouches for at each address it names.',
  ),
  'lib/features/discover/domain/seerr_known_arr.dart  .url': (
    count: 1,
    reason:
        'The Seerr a found server was read from, named in the candidate by '
        'its saved address.',
  ),
  'lib/features/pairing/domain/pair_package.dart  .url': (
    count: 3,
    reason:
        'What another device copies: each connection with an address, by '
        'the address it is saved with, and an invite\'s two addresses and '
        'their pins. Nothing here reaches it.',
  ),
  'lib/features/pairing/domain/pair_package.dart  .access': (
    count: 1,
    reason:
        'What the address away of an invite shown in person asks for, read '
        'back into the invite. Nothing here reaches it.',
  ),
  'lib/features/pairing/domain/pair_package.dart  pinForUrl(': (
    count: 1,
    reason:
        'The certificate each copied address is trusted with, copied beside '
        'it.',
  ),
  'lib/features/pairing/data/pair_session.dart  pinForUrl(': (
    count: 1,
    reason:
        'Whether this device already trusts an address an invite vouches '
        'for: an invite adds a pin, never one over another.',
  ),
  'lib/features/pairing/presentation/pair_receive_screen.dart  .url': (
    count: 1,
    reason:
        'Names each connection about to be added by the host of the address '
        'it arrives with, before anything is written. Nothing here reaches '
        'it.',
  ),
  'lib/features/prowlarr/domain/prowlarr_known_application.dart  .url': (
    count: 1,
    reason:
        'The Prowlarr a found application was read from, named in the '
        'candidate by its saved address.',
  ),
  'lib/features/dockge/presentation/dockge_provider.dart  .url': (
    count: 1,
    reason:
        'The agent lens goes back to the hub when the connection is pointed '
        'elsewhere; the route moving reaches the same hub and keeps it.',
  ),
  'lib/features/settings/data/connection_reach_provider.dart  .url': (
    count: 4,
    reason:
        'The two saved addresses nothing answered at: named by the red, and '
        'handed to the clients\' snapshot so a request to either says so; '
        'and whether a home address is on the local network, the evidence '
        'of being at home. Nothing is sent to them from here.',
  ),
  'lib/features/settings/data/route_probe.dart  .url': (
    count: 1,
    reason:
        'Which connections have an address away, and which: what makes a '
        'new probe worth running. The knocks themselves go through reachOf.',
  ),
  'lib/features/home/data/home_last_known.dart  .url': (
    count: 2,
    reason:
        'What a last drawing is valid for: the server, by the address it is '
        'saved with. The route moving reaches the same one, and its pictures '
        'draw at the address in use (resolveStoredImage).',
  ),
  'lib/features/search/presentation/global_search_provider.dart  pinForUrl(': (
    count: 1,
    reason:
        'The stamp the fan-out is rebuilt on: both addresses with their pins. '
        'Each leg watches its own route for where it asks.',
  ),

  // === Shown: a host in a sentence, the connection by its address ==========
  'lib/core/widgets/service_offline_state.dart  .url': (
    count: 1,
    reason: 'The host named under an offline service.',
  ),
  'lib/core/widgets/service_overview.dart  .url': (
    count: 1,
    reason: 'The host named on a service\'s Overview.',
  ),
  'lib/features/activity/presentation/download_page.dart  .url': (
    count: 1,
    reason: 'The download client\'s host, shown on a download\'s page.',
  ),
  'lib/features/services/presentation/service_matrix.dart  .url': (
    count: 2,
    reason: 'The host a picker cell names.',
  ),
  'lib/features/services/presentation/services_probe.dart  .url': (
    count: 2,
    reason:
        'The host a probe\'s summary names; the probe asks the route\'s '
        'address. And the host a summary only at home names: nothing is '
        'asked, and home is the only address it has.',
  ),
  'lib/features/services/presentation/services_probe.dart  urlFor(': (
    count: 1,
    reason: 'The host an offline summary names when no lens is set.',
  ),
  'lib/features/services/presentation/widgets/instance_lens_badge.dart  .url': (
    count: 2,
    reason: 'The host a lens row names.',
  ),
  'lib/features/settings/domain/unread_secret.dart  .access': (
    count: 1,
    reason: 'The kind of access a sentence about an unread secret names.',
  ),
  'lib/features/settings/presentation/requester_account_page.dart  .url': (
    count: 1,
    reason: 'The host beside the account\'s name.',
  ),
  'lib/features/settings/presentation/widgets/requester_settings_rows.dart  .url':
      (count: 2, reason: 'The hosts the requester\'s Settings rows name.'),
  'lib/features/settings/presentation/widgets/service_connection_row.dart  urlFor(':
      (count: 1, reason: 'The host a Connections row names.'),
  'lib/features/shell/domain/command_deck_entry.dart  .url': (
    count: 1,
    reason: 'The host a connection\'s entry in the command deck names.',
  ),

  // === The form, and the test of an address just typed =====================
  'lib/features/onboarding/presentation/onboarding_screen.dart  lookup.url': (
    count: 1,
    reason: 'The first-run walk resumes with the access saved at home.',
  ),
  'lib/features/onboarding/presentation/onboarding_screen.dart  urlFor(': (
    count: 3,
    reason:
        'The first-run walk shows, saves and forgets the addresses it edits.',
  ),
  'lib/features/onboarding/presentation/onboarding_screen.dart  pinForUrl(': (
    count: 2,
    reason:
        'The certificates trusted for the addresses in the walk\'s two '
        'fields.',
  ),
  'lib/features/onboarding/presentation/widgets/onboarding_found.dart  pinForUrl(':
      (
        count: 1,
        reason:
            'The certificate already trusted for the address a found service '
            'is tried at, shown beside the one it presents now: an address '
            'that is no connection yet.',
      ),
  'lib/features/settings/data/service_verification.dart  .url': (
    count: 2,
    reason:
        'diagnoseSeerr without a reach (the address at home), and the '
        'certificate probe of the form\'s own address after its test.',
  ),
  'lib/features/settings/data/service_verification.dart  pinForUrl(': (
    count: 1,
    reason: 'The certificate trusted for the form\'s address, for its probe.',
  ),
  'lib/features/settings/presentation/service_settings_screen.dart  .url': (
    count: 8,
    reason:
        'The form: its field, the address it tests and asks to trust, the '
        'labels it derives for siblings and the hosts it lists them by, and '
        'the saved address a Tracearr owner\'s session is compared with, so '
        'a connection moved to another host does not carry the bearer there.',
  ),
  'lib/features/release_search/presentation/release_search_entry.dart  .access': (
    count: 1,
    reason:
        'The settings screen names the connections behind a gateway so it can '
        'warn about background search; the search itself goes through the '
        'route.',
  ),
  'lib/features/settings/presentation/service_settings_screen.dart  .access': (
    count: 3,
    reason:
        'The form\'s Access row, filled from the access saved at home, and '
        'the access its test just sent there.',
  ),
  'lib/features/settings/presentation/service_settings_screen.dart  pinForUrl(':
      (
        count: 3,
        reason:
            'The certificate trusted for the address in the field: the trust '
            'prompt and the indicator beside it.',
      ),
  'lib/features/onboarding/presentation/requester_sign_in_screen.dart  .url': (
    count: 1,
    reason:
        'Whether a Seerr slot is empty, to sign in there rather than '
        'beside it.',
  ),
  'lib/features/settings/presentation/widgets/seerr_sign_in_flow.dart  .url': (
    count: 4,
    reason:
        'The sign-in form: the host it names, and whether its address is '
        'still the saved one (then it signs in where the route is).',
  ),
  'lib/features/settings/presentation/widgets/seerr_sign_in_flow.dart  pinForUrl(':
      (
        count: 1,
        reason:
            'The certificate trusted for the address the failed sign-in went '
            'to, for the trust prompt.',
      ),
};

/// [source] with every `//` comment line blanked.
String _withoutComments(String source) => source
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');
