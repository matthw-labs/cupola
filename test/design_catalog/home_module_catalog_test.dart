@Tags(['catalog'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/data/storage.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/home/domain/storage.dart';
import 'package:cupola/features/home/presentation/widgets/discover_shelf_module.dart';
import 'package:cupola/features/home/presentation/widgets/stack_health_module.dart';
import 'package:cupola/features/home/presentation/widgets/storage_module.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/arrived_last_known.dart';
import 'package:cupola/features/home/data/last_known/coming_up_last_known.dart';
import 'package:cupola/features/home/data/last_known/downloads_last_known.dart';
import 'package:cupola/features/home/presentation/widgets/home_as_of_line.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/needs_you.dart';
import 'package:cupola/features/home/presentation/widgets/arrived_module.dart';
import 'package:cupola/features/home/presentation/widgets/coming_up_module.dart';
import 'package:cupola/features/home/presentation/widgets/continue_watching_module.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/home/presentation/widgets/now_playing_module.dart';
import 'package:cupola/features/home/presentation/widgets/requests_module.dart';
import 'package:cupola/features/home/presentation/widgets/set_up_next_module.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/onboarding/data/known_candidates_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';

import '../test_helpers/settings_scope.dart';
import 'calendar_world.dart';
import 'catalog.dart';

final _now = DateTime(2026, 9, 29, 20, 53);

DashboardDecision _fault(
  DecisionKind kind,
  String title, {
  int count = 1,
  ServiceKey service = ServiceKey.radarr,
}) => DashboardDecision(
  kind: kind,
  id: '${kind.name}-$title',
  service: service,
  title: title,
  detail: '',
  occurredAt: null,
  count: count,
);

NeedsYou _needs({
  List<ServiceKey> silent = const [],
  required List<DashboardDecision> decisions,
}) => needsYouOf(
  silent: silent,
  decisions: decisions,
  now: _now,
  silentAt: _now,
)!;

ServiceQueueItem _download(
  String title,
  String release, {
  required String id,
  double? progress,
  int? eta,
  InFlightFault? fault,
  bool queued = false,
  ServiceKey service = ServiceKey.radarr,
}) => ServiceQueueItem(
  service: service,
  id: id,
  title: title,
  progress: progress,
  clientLabel: 'qBittorrent',
  etaSeconds: eta,
  fault: fault,
  queued: queued,
  clientService: ServiceKey.qbittorrent,
  posterUrl: CatalogArt.poster,
  names: MediaNames(
    title: title,
    machineName: release,
    machineKind: MachineNameKind.release,
  ),
);

/// Three moving, one stuck and one waiting its turn, as the household's
/// evening has them.
final _evening = (
  preview: [
    _download(
      'Cosmos Laundromat · S2 E4',
      'Cosmos.Laundromat.S02E04.1080p.WEB',
      id: '1',
      progress: 0.88,
      eta: 60,
      service: ServiceKey.sonarr,
    ),
    _download(
      'Sprite Fright',
      'Sprite.Fright.2021.1080p.WEB',
      id: '2',
      progress: 0.62,
      eta: 660,
    ),
    _download(
      'Elephants Dream',
      'Elephants.Dream.2006.2160p.BluRay',
      id: '3',
      progress: 0.31,
      eta: 360,
    ),
  ],
  activeCount: 3,
  movingCount: 3,
  queued: [
    _download(
      'Sintel · 2160p',
      'Sintel.2010.2160p.BluRay',
      id: '5',
      progress: 0,
      queued: true,
    ),
  ],
  faults: [
    _download(
      'Big Buck Bunny',
      'Big.Buck.Bunny.2008.1080p.BluRay',
      id: '4',
      progress: 0.47,
      fault: InFlightFault.stalled,
    ),
  ],
  held: 0,
  rateBytesPerSecond: 40400000,
  clients: 2,
  coverage: SourceCoverage.none,
);

final _noHistory = (
  entries: const <ArrHistoryEntry>[],
  coverage: SourceCoverage.none,
);

final _clientSettings = settingsWithServices(const [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.seerr,
  ServiceKey.qbittorrent,
  ServiceKey.jellyfin,
]);

DashboardDecision _request(String title, int id, String detail, int hours) =>
    DashboardDecision(
      kind: DecisionKind.pendingRequest,
      id: 'seerr--$id',
      service: ServiceKey.seerr,
      title: title,
      detail: detail,
      // The row says when against the clock it is drawn on.
      occurredAt: catalogNow.subtract(Duration(hours: hours)),
      actionId: id,
      posterUrl: CatalogArt.poster,
    );

class _Answered extends AnsweredRequests {
  _Answered(this.initial);

  final Map<String, AnsweredRequest> initial;

  @override
  Map<String, AnsweredRequest> build() => initial;
}

StreamActivityRow _playing(
  String user,
  String title,
  String device,
  int minutesLeft,
  double progress, {
  String? subtitle,
  bool paused = false,
}) => StreamActivityRow(
  service: ServiceKey.jellyfin,
  instanceId: '',
  connectionName: null,
  session: StreamSession(
    id: '$user-$title',
    userName: user,
    title: title,
    subtitle: subtitle,
    deviceLabel: device,
    posterPath: null,
    playMethod: StreamPlayMethod.directPlay,
    transcodeReasons: const [],
    bitrate: null,
    bitrateIsNominal: true,
    progress: progress,
    isPaused: paused,
    remaining: Duration(minutes: minutesLeft),
  ),
);

/// A playback only Tracearr sees: Luca's Elephants Dream on a Plex Cupola is
/// not connected to, marked as coming through Tracearr.
StreamActivityRow _through(
  String user,
  String title,
  String device,
  int minutesLeft,
  double progress,
) => StreamActivityRow(
  service: ServiceKey.plex,
  instanceId: 'tracearr',
  connectionName: null,
  through: ServiceKey.tracearr,
  session: StreamSession(
    id: '$user-$title',
    userName: user,
    title: title,
    subtitle: null,
    deviceLabel: device,
    posterPath: null,
    playMethod: StreamPlayMethod.directPlay,
    transcodeReasons: const [],
    bitrate: null,
    bitrateIsNominal: true,
    progress: progress,
    isPaused: false,
    remaining: Duration(minutes: minutesLeft),
  ),
);

final _tracearrSettings = settingsWithServices(const [
  ServiceKey.jellyfin,
  ServiceKey.tracearr,
]);

/// The calendar of the boards' household, as Coming up reads it.
LibraryCalendar _calendar(
  List<CalendarEvent> events, {
  List<CalendarSilence> silent = const [],
}) => LibraryCalendar(
  window: CalendarWorld.window,
  events: events,
  answered: const ['Radarr', 'Radarr 4K', 'Sonarr'],
  silent: silent,
  kinds: const {CalendarKind.movie, CalendarKind.episode, CalendarKind.album},
  readAt: CalendarWorld.now,
);

ArrHistoryEntry _arrival(
  String title, {
  required Duration ago,
  required int tmdbId,
  String? connectionName,
}) => ArrHistoryEntry(
  service: ServiceKey.radarr,
  id: tmdbId,
  mediaId: tmdbId,
  title: title,
  unitId: null,
  detail: null,
  posterUrl: CatalogArt.poster,
  backdropUrl: CatalogArt.backdrop,
  outcome: ArrImportOutcome.imported,
  at: _now.subtract(ago),
  reason: null,
  instanceId: connectionName ?? 'radarr',
  connectionName: connectionName,
  tmdbId: tmdbId,
);

/// The week the boards' household had: four titles, two on the 4K Radarr.
final _week = [
  _arrival(
    'Spring',
    ago: const Duration(hours: 2),
    tmdbId: 1,
    connectionName: '4K',
  ),
  _arrival('Coffee Run', ago: const Duration(hours: 9), tmdbId: 2),
  _arrival(
    'Tears of Steel',
    ago: const Duration(days: 1),
    tmdbId: 3,
    connectionName: '4K',
  ),
  _arrival('Sintel', ago: const Duration(days: 2), tmdbId: 4),
];

ResumeRow _resume(
  String title,
  String subtitle, {
  required int season,
  required int episode,
  required int runtimeMinutes,
  required int atMinute,
}) => (
  service: ServiceKey.jellyfin,
  instanceId: '',
  connectionName: null,
  item: StreamItem(
    id: '$title-$season-$episode',
    title: title,
    subtitle: subtitle,
    kind: StreamItemKind.episode,
    posterPath: null,
    year: null,
    runtimeMs: runtimeMinutes * 60000,
    isPlayed: false,
    resumeOffsetMs: atMinute * 60000,
    unplayedChildCount: null,
    seasonNumber: season,
    episodeNumber: episode,
  ),
);

/// Rows standing in for a module's own: the frame does not own them.
class _Rows extends StatelessWidget {
  const _Rows(this.rows);

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, (title, line)) in rows.indexed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: index > 0
                  ? Border(top: BorderSide(color: room.hair))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.row.copyWith(color: room.ink)),
                  Text(
                    line,
                    style: AppType.meta.copyWith(color: room.inkSecondary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A household's twelve services, in the Stack's order, each answering unless
/// [lights] says otherwise.
StackLights _lights(
  Map<ServiceKey, StackLight> lights, {
  StackLight every = StackLight.answering,
}) => StackLights(
  rows: [
    for (final service in const [
      ServiceKey.seerr,
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.prowlarr,
      ServiceKey.bazarr,
      ServiceKey.qbittorrent,
      ServiceKey.sabnzbd,
      ServiceKey.jellyfin,
      ServiceKey.truenas,
      ServiceKey.dockge,
      ServiceKey.nginxProxyManager,
    ])
      (service: service, light: lights[service] ?? every),
  ],
);

const _tib = 1024 * 1024 * 1024 * 1024;

final _pools = [
  StoragePool(
    service: ServiceKey.truenas,
    instanceId: 'truenas',
    name: 'tank',
    healthy: false,
    state: 'Degraded',
    usedFraction: 0.72,
    usedBytes: (31.2 * _tib).round(),
    totalBytes: (43.6 * _tib).round(),
    disks: const ['Disk sdd reports 8 errors'],
  ),
  StoragePool(
    service: ServiceKey.truenas,
    instanceId: 'truenas',
    name: 'fast',
    healthy: true,
    state: 'Healthy',
    scan: 'scrubbed Sunday',
    usedFraction: 0.33,
    usedBytes: (0.6 * _tib).round(),
    totalBytes: (1.8 * _tib).round(),
  ),
];

void main() {
  catalogCard(
    'HomeModule',
    width: 840,
    overrides: () async => settingsScopeOverrides(
      configured: const [
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.seerr,
      ],
    ),
    scenes: [
      CatalogScene(
        'HomeModuleFrame · ready: the name, the line under it, the rows in '
        'the slab',
        (_) => const HomeModuleFrame(
          title: 'Requests',
          subtitle: '2 wait for you',
          child: _Rows([
            ('Charge', 'Anna · 2 h ago'),
            ('Metropolis', 'Luca · yesterday'),
          ]),
        ),
        width: 390,
      ),
      CatalogScene(
        'HomeModuleFrame.loading · the name over the shape of its rows, never '
        'a spinner',
        (_) => const HomeModuleFrame.loading(title: 'Downloads'),
        width: 390,
      ),
      CatalogScene(
        'HomeModuleFrame.silent · its sources did not answer: it keeps its '
        'place and names the service, with Retry',
        (_) => HomeModuleFrame.silent(
          title: 'Arrived',
          coverage: SourceCoverage.failure(
            ServiceKey.radarr,
            const ClassifiedFailure(ServiceFailureReason.unreachable),
          ),
          onRetry: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'HomeModuleFrame.silent · away from home, its service has no address '
        'away: a grey line over the last drawing, no band, no Retry',
        (_) => LastKnownWords(
          words: 'As of 20:41',
          child: HomeModuleFrame.silent(
            title: 'Arrived',
            coverage: SourceCoverage.failure(
              ServiceKey.lidarr,
              const ClassifiedFailure(ServiceFailureReason.onlyAtHome),
            ),
            onRetry: () {},
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Sintel · Elephants Dream · Spring'),
            ),
          ),
        ),
        width: 390,
      ),
      CatalogScene(
        'HomeModuleFrame.needsService · switched on in Edit Home without its '
        'service: dimmed, a target, the service named',
        (_) => HomeModuleFrame.needsService(
          title: 'Storage',
          service: ServiceKey.truenas,
          headline: 'Set up TrueNAS to see your storage',
          setUpLine: 'Pools, space and disk health',
          onSetUp: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Needs you · the largest group of equal faults leads, two more '
        'things wait, Review',
        (_) => NeedsYouLine(
          needs: _needs(
            decisions: [
              _fault(DecisionKind.stalledDownload, 'Big Buck Bunny'),
              _fault(
                DecisionKind.importBlocked,
                'Cosmos Laundromat',
                count: 18,
                service: ServiceKey.sonarr,
              ),
              _fault(DecisionKind.failingIndexer, 'media'),
            ],
          ),
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Needs you · one fault: no count',
        (_) => NeedsYouLine(
          needs: _needs(
            decisions: [_fault(DecisionKind.stalledDownload, 'Big Buck Bunny')],
          ),
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Needs you · connections that failed alike lead as one sentence, '
        'counted once',
        (_) => NeedsYouLine(
          needs: _needs(
            decisions: [
              for (final service in [
                ServiceKey.seerr,
                ServiceKey.radarr,
                ServiceKey.sonarr,
                ServiceKey.lidarr,
                ServiceKey.prowlarr,
                ServiceKey.qbittorrent,
              ])
                DashboardDecision(
                  kind: DecisionKind.connectionFault,
                  id: 'connection-${service.name}',
                  service: service,
                  title:
                      '${service.title} was reached but did not reply in '
                      'time',
                  detail: '',
                  occurredAt: null,
                  failureReason: ServiceFailureReason.timeout,
                ),
              _fault(DecisionKind.failingIndexer, 'media'),
            ],
          ),
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Needs you · a service that did not answer leads, in red, with its '
        'time and Retry',
        (_) => NeedsYouLine(
          needs: _needs(
            silent: const [ServiceKey.radarr],
            decisions: [
              _fault(DecisionKind.importBlocked, 'x', count: 18),
              _fault(DecisionKind.stalledDownload, 'Big Buck Bunny'),
              _fault(DecisionKind.failingIndexer, 'media'),
            ],
          ),
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Set up next · Radarr, Sonarr and Seerr set up: what each missing '
        'service adds, then All services',
        (_) => const SetUpNextModule(),
        width: 390,
      ),
      CatalogScene(
        'Set up next · what Seerr and Prowlarr know comes first, its line led '
        'by a key; Radarr 4K is added beside the Radarr set up',
        (_) => const SetUpNextModule(),
        width: 390,
        overrides: [
          foundCandidatesProvider.overrideWith(
            (ref) async => const [
              ConnectionCandidate(
                service: ServiceKey.radarr,
                name: 'Radarr 4K',
                reportedUrl: 'http://nas.lan:7879',
                source: CandidateSource(
                  service: ServiceKey.seerr,
                  connectionId: 'seerr',
                  url: 'http://nas.lan:5055',
                ),
                apiKey: 'catalog-key',
              ),
              ConnectionCandidate(
                service: ServiceKey.lidarr,
                name: 'Lidarr',
                reportedUrl: 'http://nas.lan:8686',
                source: CandidateSource(
                  service: ServiceKey.prowlarr,
                  connectionId: 'prowlarr',
                  url: 'http://nas.lan:9696',
                ),
              ),
            ],
          ),
        ],
      ),
      CatalogScene(
        'Downloads · what moves, how far and how long; the stuck one in '
        'amber with the remedy Needs you chooses and More; what waits its '
        'turn is counted after it (`1 queued`) and has no row',
        (_) => const HomeDownloadsModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          servicesInFlightProvider.overrideWith((ref) async => _evening),
          servicesArrHistoryProvider.overrideWith((ref) async => _noHistory),
        ],
      ),
      CatalogScene(
        'Downloads · qBittorrent did not answer: the speed is a dash, the '
        'rows keep what the arrs know',
        (_) => const HomeDownloadsModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          servicesInFlightProvider.overrideWith(
            (ref) async => (
              preview: _evening.preview,
              activeCount: 3,
              movingCount: 3,
              queued: const <ServiceQueueItem>[],
              faults: const <ServiceQueueItem>[],
              held: 0,
              rateBytesPerSecond: null,
              clients: 0,
              coverage: SourceCoverage.merge([
                SourceCoverage.answeredBy(ServiceKey.radarr),
                SourceCoverage.failure(
                  ServiceKey.qbittorrent,
                  const ClassifiedFailure(ServiceFailureReason.unreachable),
                ),
              ]),
            ),
          ),
          servicesArrHistoryProvider.overrideWith((ref) async => _noHistory),
        ],
      ),
      CatalogScene(
        'Downloads · nothing moving: a calm line and when the last download '
        'finished',
        (_) => const HomeDownloadsModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          servicesInFlightProvider.overrideWith(
            (ref) async => (
              preview: const <ServiceQueueItem>[],
              activeCount: 0,
              movingCount: 0,
              queued: const <ServiceQueueItem>[],
              faults: const <ServiceQueueItem>[],
              held: 0,
              rateBytesPerSecond: 0,
              clients: 1,
              coverage: SourceCoverage.none,
            ),
          ),
          servicesArrHistoryProvider.overrideWith(
            (ref) async => (
              entries: [
                ArrHistoryEntry(
                  service: ServiceKey.radarr,
                  id: 1,
                  mediaId: 1,
                  title: 'Spring',
                  unitId: null,
                  detail: '',
                  posterUrl: '',
                  outcome: ArrImportOutcome.imported,
                  at: catalogNow.subtract(const Duration(days: 1)),
                  reason: null,
                ),
              ],
              coverage: SourceCoverage.none,
            ),
          ),
        ],
      ),
      CatalogScene(
        'Requests · Charge approved here keeps its row, saying where it went; '
        'Metropolis still waits with Approve and Decline',
        (_) => const HomeRequestsModule(),
        width: 390,
        overrides: [
          dashboardDecisionSourceProvider.overrideWith(
            (ref, source) async => (
              decisions: [_request('Metropolis', 2, 'Luca', 20)],
              coverage: SourceCoverage.none,
            ),
          ),
          pendingRequestCountProvider.overrideWith(
            (ref) async => (count: 1, floor: false),
          ),
          answeredRequestsProvider.overrideWith(
            () => _Answered({
              'seerr--1': (
                decision: _request('Charge', 1, 'Anna', 2),
                outcome: 'Approved · sent to Radarr',
              ),
            }),
          ),
        ],
      ),
      CatalogScene(
        'Now playing · who, what, on which screen and how long is left, over '
        'an ink bar',
        (_) => const HomeNowPlayingModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          streamActivityProvider.overrideWith(
            (ref) async => [
              _playing('Anna', 'Sintel', 'Living room TV', 9, 0.4),
              _playing(
                'Luca',
                'Cosmos Laundromat',
                'Infuse · iPhone',
                5,
                0.8,
                subtitle: 'S2 E3 · The Second Cycle',
                paused: true,
              ),
            ],
          ),
          streamActivityOfflineProvider.overrideWith(
            (ref) async => const <StreamOfflineSource>[],
          ),
        ],
      ),
      CatalogScene(
        'Now playing · with Tracearr: the Jellyfin playback is one row, the '
        'Plex playback only Tracearr sees says so first on its line, and '
        'the header names it once',
        (_) => const HomeNowPlayingModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _tracearrSettings),
          streamActivityProvider.overrideWith(
            (ref) async => [
              _playing('Anna', 'Sintel', 'Living room TV', 9, 0.4),
              _through(
                'Luca',
                'Elephants Dream',
                'Plex for iOS\u00A0· iPad',
                7,
                0.6,
              ),
            ],
          ),
          streamActivityOfflineProvider.overrideWith(
            (ref) async => const <StreamOfflineSource>[],
          ),
        ],
      ),
      CatalogScene(
        'Now playing · Tracearr did not answer: the Jellyfin rows stay, and '
        'one line says Tracearr did not answer and what is missing',
        (_) => const HomeNowPlayingModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _tracearrSettings),
          streamActivityProvider.overrideWith(
            (ref) async => [
              _playing('Anna', 'Sintel', 'Living room TV', 9, 0.4),
            ],
          ),
          streamActivityOfflineProvider.overrideWith(
            (ref) async => const [
              (
                service: ServiceKey.tracearr,
                instanceId: 'tracearr',
                title: 'Tracearr',
                error: ClassifiedFailure(ServiceFailureReason.unreachable),
              ),
            ],
          ),
        ],
      ),
      CatalogScene(
        'Continue watching · the series, the episode and how long is left, '
        'over an ink bar',
        (_) => const HomeContinueWatchingModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          homeResumeProvider.overrideWith(
            (ref) async => (
              rows: [
                _resume(
                  'The Second Cycle',
                  'Cosmos Laundromat · S2 E3',
                  season: 2,
                  episode: 3,
                  runtimeMinutes: 24,
                  atMinute: 19,
                ),
                _resume(
                  'Harbour Lights',
                  'Night Shift · S1 E2',
                  season: 1,
                  episode: 2,
                  runtimeMinutes: 48,
                  atMinute: 12,
                ),
              ],
              coverage: SourceCoverage.answeredBy(ServiceKey.jellyfin),
              viewerMissing: const <String>[],
            ),
          ),
        ],
      ),
      CatalogScene(
        'Continue watching · a server key and nobody chosen: Which Jellyfin '
        'user are you?',
        (_) => const HomeContinueWatchingModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          homeResumeProvider.overrideWith(
            (ref) async => (
              rows: const <ResumeRow>[],
              coverage: SourceCoverage.none,
              viewerMissing: const ['jellyfin'],
            ),
          ),
        ],
      ),
      CatalogScene(
        'Coming up · today to Friday, three rows, the day leading and an '
        'episode\'s time in its status',
        (_) => const HomeComingUpModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          libraryCalendarProvider.overrideWith(
            (ref) async => _calendar(CalendarWorld.events),
          ),
        ],
      ),
      CatalogScene(
        'Coming up · Lidarr did not answer, and nothing else by Friday: named, '
        'then the calm line',
        (_) => const HomeComingUpModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          libraryCalendarProvider.overrideWith(
            (ref) async => _calendar(
              [CalendarWorld.disc],
              silent: const [
                (
                  service: ServiceKey.lidarr,
                  connectionId: 'lidarr',
                  name: 'Lidarr',
                  error: ClassifiedFailure(ServiceFailureReason.unreachable),
                ),
              ],
            ),
          ),
        ],
      ),
      CatalogScene(
        'Arrived · the last seven days, one wide card per title, the newest '
        'first',
        (_) => const HomeArrivedModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          arrivalsClockProvider.overrideWithValue(() => _now),
          servicesArrivalsProvider.overrideWith(
            (ref) async => (
              entries: _week,
              coverage: SourceCoverage.answeredBy(ServiceKey.radarr),
            ),
          ),
        ],
      ),
      CatalogScene(
        'Arrived · Radarr 4K did not answer: the count says who it is from',
        (_) => const HomeArrivedModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          arrivalsClockProvider.overrideWithValue(() => _now),
          servicesArrivalsProvider.overrideWith(
            (ref) async => (
              entries: [
                for (final entry in _week)
                  if (entry.connectionName == null) entry,
              ],
              coverage: SourceCoverage.merge([
                SourceCoverage.answeredBy(
                  ServiceKey.radarr,
                  instanceId: 'radarr',
                ),
                SourceCoverage.failure(
                  ServiceKey.radarr,
                  const ClassifiedFailure(ServiceFailureReason.unreachable),
                  instanceId: '4K',
                  name: '4K',
                ),
              ]),
            ),
          ),
        ],
      ),
      CatalogScene(
        'Last known · a cold start: Arrived as it was last drawn, under the '
        'Home\'s one line, while its live read is asked for',
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [HomeAsOfLine(), HomeArrivedModule()],
        ),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          arrivalsClockProvider.overrideWithValue(() => _now),
          calendarClockProvider.overrideWithValue(() => _now),
          lastKnownStoreProvider.overrideWithValue(
            LastKnownStore.memory()..write(
              homeLastKnownKey(Audience.operator.name, arrivedLastKnown),
              validity: homeLastKnownValidity(
                _clientSettings,
                arrivedLastKnown.services,
              ),
              schema: arrivedLastKnown.schema,
              data: arrivedLastKnown.encode((
                entries: _week,
                coverage: SourceCoverage.answeredBy(ServiceKey.radarr),
              ), _keep),
              takenAt: _now.subtract(const Duration(minutes: 47)),
            ),
          ),
          servicesArrivalsProvider.overrideWith(
            (ref) => Completer<ArrHistory>().future,
          ),
        ],
      ),
      CatalogScene(
        'Last known · a cold start: Coming up as it was last drawn, a download '
        'as the state it was in with no figure, under the Home\'s one line',
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [HomeAsOfLine(), HomeComingUpModule()],
        ),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          calendarClockProvider.overrideWithValue(() => _now),
          lastKnownStoreProvider.overrideWithValue(
            LastKnownStore.memory()..write(
              homeLastKnownKey(Audience.operator.name, comingUpLastKnown),
              validity: homeLastKnownValidity(
                _clientSettings,
                comingUpLastKnown.services,
              ),
              schema: comingUpLastKnown.schema,
              data: comingUpLastKnown.encode(
                _calendar(CalendarWorld.events),
                _keep,
              ),
              takenAt: _now.subtract(const Duration(minutes: 47)),
            ),
          ),
          libraryCalendarProvider.overrideWith(
            (ref) => Completer<LibraryCalendar>().future,
          ),
        ],
      ),
      CatalogScene(
        'Last known · a cold start: Downloads as it was last drawn, how far '
        'each got and the bar where it stopped, in a neutral; no time left, '
        'no speed, and the row that was stuck is a plain row with no remedy',
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [HomeAsOfLine(), HomeDownloadsModule()],
        ),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          calendarClockProvider.overrideWithValue(() => _now),
          stallClockProvider.overrideWithValue(() => _now),
          lastKnownStoreProvider.overrideWithValue(
            LastKnownStore.memory()..write(
              homeLastKnownKey(Audience.operator.name, downloadsLastKnown),
              validity: homeLastKnownValidity(
                _clientSettings,
                downloadsLastKnown.services,
              ),
              schema: downloadsLastKnown.schema,
              data: downloadsLastKnown.encode(
                downloadsDrawingOf(_evening),
                _keep,
              ),
              takenAt: _now.subtract(const Duration(minutes: 47)),
            ),
          ),
          servicesInFlightProvider.overrideWith(
            (ref) => Completer<ServicesInFlight>().future,
          ),
          servicesArrHistoryProvider.overrideWith((ref) async => _noHistory),
        ],
      ),
      CatalogScene(
        'EditHomeRow · the way to Edit Home, at the foot of the operator\'s '
        'Home',
        (_) => const EditHomeRow(),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · Needs you, Set up next and Downloads wrap and keep '
        'their targets',
        (_) => Column(
          children: [
            NeedsYouLine(
              needs: _needs(
                decisions: [
                  _fault(DecisionKind.importBlocked, 'x', count: 18),
                  _fault(DecisionKind.failingIndexer, 'media'),
                ],
              ),
              onTap: () {},
            ),
            const SetUpNextModule(),
            const HomeDownloadsModule(),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          servicesInFlightProvider.overrideWith((ref) async => _evening),
          servicesArrHistoryProvider.overrideWith((ref) async => _noHistory),
        ],
      ),
      CatalogScene(
        'Stack health · every service its mark and its light; the faults, '
        'one per amber light, named in amber; one target to Stack',
        (_) => const HomeStackHealthModule(),
        width: 390,
        overrides: [
          stackLightsProvider.overrideWithValue(
            _lights({
              ServiceKey.sonarr: StackLight.fault,
              ServiceKey.qbittorrent: StackLight.fault,
              ServiceKey.truenas: StackLight.fault,
            }),
          ),
        ],
      ),
      CatalogScene(
        'Stack health · one did not answer: its light red, the line red '
        'with Retry',
        (_) => const HomeStackHealthModule(),
        width: 390,
        overrides: [
          stackLightsProvider.overrideWithValue(
            _lights({
              ServiceKey.radarr: StackLight.silent,
              ServiceKey.sonarr: StackLight.fault,
            }),
          ),
        ],
      ),
      CatalogScene(
        'Stack health · reached and never replied: amber lights out of the '
        'count, one amber sentence with Retry',
        (_) => const HomeStackHealthModule(),
        width: 390,
        overrides: [
          stackLightsProvider.overrideWithValue(
            _lights({
              ServiceKey.radarr: StackLight.stuck,
              ServiceKey.sonarr: StackLight.stuck,
              ServiceKey.qbittorrent: StackLight.answering,
            }),
          ),
        ],
      ),
      CatalogScene(
        'Stack health · before anything answers: hollow lights',
        (_) => const HomeStackHealthModule(),
        width: 390,
        overrides: [
          stackLightsProvider.overrideWithValue(
            _lights(const {}, every: StackLight.checking),
          ),
        ],
      ),
      CatalogScene(
        'Storage · each pool its share in ink, its state, and the disk in '
        'trouble in amber, one tap from its pool',
        (_) => const HomeStorageModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(const [ServiceKey.truenas]),
          ),
          homeStorageProvider.overrideWith(
            (ref) async => (
              pools: _pools,
              coverage: SourceCoverage.answeredBy(ServiceKey.truenas),
            ),
          ),
        ],
      ),
      CatalogScene(
        'Storage · TrueNAS did not answer: the place kept, Retry',
        (_) => const HomeStorageModule(),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(const [ServiceKey.truenas]),
          ),
          homeStorageProvider.overrideWith(
            (ref) async => (
              pools: const <StoragePool>[],
              coverage: SourceCoverage.failure(
                ServiceKey.truenas,
                const ClassifiedFailure(ServiceFailureReason.unreachable),
              ),
            ),
          ),
        ],
      ),
      CatalogScene(
        'Storage and Discover shelf switched on without their services: '
        'each asks for it, in a dashed outline',
        (_) => const Column(
          children: [HomeStorageModule(), HomeDiscoverShelfModule()],
        ),
        width: 390,
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(const [ServiceKey.radarr]),
          ),
        ],
      ),
      CatalogScene(
        'Text at 200% · Stack health, Storage, and Discover shelf asking '
        'for Seerr: the button under the words',
        (_) => const Column(
          children: [
            HomeStackHealthModule(),
            HomeStorageModule(),
            HomeDiscoverShelfModule(),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(const [ServiceKey.truenas]),
          ),
          stackLightsProvider.overrideWithValue(
            _lights({ServiceKey.truenas: StackLight.fault}),
          ),
          homeStorageProvider.overrideWith(
            (ref) async => (
              pools: _pools.take(1).toList(),
              coverage: SourceCoverage.answeredBy(ServiceKey.truenas),
            ),
          ),
        ],
      ),
      CatalogScene(
        'Text at 200% · Continue watching, Coming up and Arrived',
        (_) => const Column(
          children: [
            HomeContinueWatchingModule(),
            HomeComingUpModule(),
            HomeArrivedModule(),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _clientSettings),
          homeResumeProvider.overrideWith(
            (ref) async => (
              rows: [
                _resume(
                  'The Second Cycle',
                  'Cosmos Laundromat · S2 E3',
                  season: 2,
                  episode: 3,
                  runtimeMinutes: 24,
                  atMinute: 19,
                ),
              ],
              coverage: SourceCoverage.answeredBy(ServiceKey.jellyfin),
              viewerMissing: const <String>[],
            ),
          ),
          libraryCalendarProvider.overrideWith(
            (ref) async => _calendar(CalendarWorld.events),
          ),
          arrivalsClockProvider.overrideWithValue(() => _now),
          servicesArrivalsProvider.overrideWith(
            (ref) async => (
              entries: _week,
              coverage: SourceCoverage.answeredBy(ServiceKey.radarr),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Keeps the pictures as the Home does, against the client's connections.
final _keep = storedImageKeeper(_clientSettings);
