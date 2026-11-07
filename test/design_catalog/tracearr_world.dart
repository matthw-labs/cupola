import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart' show TracearrFake;
import 'package:cupola/demo/world/fixtures.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_filters.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session_sheet.dart';

import 'catalog.dart';
import 'emby_world.dart';

/// Tracearr's whole screens, as the card draws them: the demo world's
/// `TracearrFake` answers through the app's own client for the people, the
/// history, the violations and the figures (`emby_world.dart` starts the
/// world and scopes each scene to it), and three reads are written here
/// because the world has no such state: a server whose token Tracearr was
/// refused on, a transcode with its reason, and an unseen count that is a
/// floor.
///
/// Dated from [catalogNow] where the words are the hour's (`2 h ago`), so a
/// render is the same within the hour.

/// A scene on the world, with the live feed off: its event stream is a
/// connection the page holds open, and the rows are the ones written below.
Widget tracearrWorldScene(Widget child, {List<Override> overrides = const []}) {
  final streams = _streams();
  return EmbyWorldScope(
    overrides: [
      tracearrLiveFeedProvider.overrideWith((ref) {}),
      tracearrLiveProvider.overrideWith(() => _ScriptedLive(streams)),
      ...overrides,
    ],
    child: child,
  );
}

/// The Overview's own reads: three servers, one of them refused Tracearr's
/// token (so *Servers* reads 2 of 3), and an unseen page with another after
/// it, so *Unseen* is a floor.
final List<Override> tracearrOverviewOverrides = [
  tracearrServersProvider.overrideWith((ref) async => _servers()),
  tracearrUnseenViolationsProvider.overrideWith((ref) async => _unseenFloor()),
];

/// History as a person left it: Anna, the last seven days, only what she
/// watched.
///
/// With its own rows too: the world dates its viewings from the real clock,
/// and a row says the time of day, so Anna's are written here on the calendar
/// (today, yesterday, the day before) and read the same at any hour.
final List<Override> tracearrRememberedHistory = [
  tracearrHistoryFiltersProvider.overrideWith(_Remembered.new),
  tracearrHistoryProvider.overrideWith(_ScriptedHistory.new),
];

class _ScriptedHistory extends TracearrHistoryList {
  @override
  Future<TracearrRows<TracearrHistoryEntry>> build() async {
    final template =
        (jsonFixtureMap('tracearr/history_page.json')['data'] as List).first
            as Map<String, dynamic>;
    final today = DateTime(catalogNow.year, catalogNow.month, catalogNow.day);
    TracearrHistoryEntry row(
      int n,
      String title,
      int year,
      DateTime start,
      int minutes,
      String device,
    ) {
      final stop = start.add(Duration(minutes: minutes));
      return TracearrHistoryEntry.fromJson({
        ...template,
        'id': 'e0e0e0e0-000$n-4000-8000-000000000000',
        'reference_id': 'e0e0e0e0-000$n-4000-8000-00000000ffff',
        'server_id': TracearrFake.embyServerId,
        'server_name': 'tower',
        'server_type': 'emby',
        'media_title': title,
        'year': year,
        'poster_url': null,
        'avatar_url': null,
        'device': device,
        'started_at': start.toUtc().toIso8601String(),
        'stopped_at': stop.toUtc().toIso8601String(),
        'duration_ms': Duration(minutes: minutes).inMilliseconds,
        'watched': true,
        'percent_complete': 100,
        'user': {
          'id': TracearrFake.annaId,
          'server_user_id': 'account-Anna-emby',
          'username': 'Anna',
          'thumb_url': null,
          'avatar_url': null,
        },
      });
    }

    return TracearrRows(
      items: [
        row(
          1,
          'Sintel',
          2010,
          today.add(const Duration(hours: 9, minutes: 10)),
          15,
          'Living Room TV',
        ),
        row(
          2,
          'Tears of Steel',
          2012,
          today.add(const Duration(hours: 8)),
          12,
          'Living Room TV',
        ),
        row(
          3,
          'Big Buck Bunny',
          2008,
          today.subtract(const Duration(hours: 3)),
          10,
          'Emby Web',
        ),
        row(
          4,
          'Elephants Dream',
          2006,
          today.subtract(const Duration(hours: 4, minutes: 30)),
          11,
          'Emby Web',
        ),
        row(
          5,
          'Cosmos Laundromat',
          2015,
          today.subtract(const Duration(days: 1, hours: 3)),
          12,
          'Living Room TV',
        ),
      ],
    );
  }
}

class _Remembered extends TracearrHistoryFiltersNotifier {
  @override
  TracearrHistoryFilters build() => const TracearrHistoryFilters(
    userId: TracearrFake.annaId,
    userName: 'Anna',
    period: TracearrPeriod.last7,
    onlyWatched: true,
  );
}

class _ScriptedLive extends TracearrLiveNotifier {
  _ScriptedLive(this.streams);

  final TracearrStreams streams;

  @override
  Future<TracearrStreams> build() async => streams;
}

TracearrServers _servers() => TracearrServers.fromJson({
  'tracearr_version': TracearrFake.version,
  'data': [
    for (final (id, name, type, status, reason) in [
      (
        TracearrFake.jellyfinServerId,
        'nas',
        'jellyfin',
        'down',
        'unauthorized',
      ),
      (TracearrFake.plexServerId, 'basement-nas', 'plex', 'up', null),
      (TracearrFake.embyServerId, 'tower', 'emby', 'up', null),
    ])
      {
        'server_id': id,
        'server_name': name,
        'server_type': type,
        'status': status,
        'reason': reason,
        'historical': false,
        'active_streams': status == 'up' ? 1 : 0,
        'version': null,
      },
  ],
});

TracearrPage<TracearrViolation> _unseenFloor() => TracearrPage(
  items: [
    for (var i = 0; i < 25; i++)
      TracearrViolation.fromJson({
        'id':
            '00000000-0000-4000-8000-0000000001${i.toString().padLeft(2, '0')}',
        'severity': 'low',
        'created_at': catalogNow
            .subtract(Duration(hours: i + 1))
            .toIso8601String(),
        'rule': {'id': 'rule-$i', 'name': 'Unknown device'},
        'server': {
          'id': TracearrFake.plexServerId,
          'name': 'basement-nas',
          'type': 'plex',
        },
        'user': {'id': TracearrFake.lucaId, 'username': 'Luca'},
      }),
  ],
  nextCursor: '25',
  pageSize: 25,
);

/// Three streams on the household's servers: Anna's film on a Plex through a
/// transcode (the video re-encoded, with the server's reason), Luca's episode
/// paused on an Emby, and Anna's second film direct on the same Emby. The
/// rows are the hand-written `streams.json`, whose shapes are the ones
/// Tracearr 3.1.4 sends, written onto the household.
TracearrStreams _streams() {
  final rows = [
    for (final row in jsonFixtureMap('tracearr/streams.json')['data'] as List)
      {...(row as Map<String, dynamic>), 'poster_url': null},
  ];
  String ago(Duration age) =>
      catalogNow.subtract(age).toUtc().toIso8601String();
  final transcode = {
    ...rows[0],
    'server_id': TracearrFake.plexServerId,
    'server_name': 'basement-nas',
    'started_at': ago(const Duration(hours: 2)),
  };
  final paused = {
    ...rows[1],
    'server_id': TracearrFake.embyServerId,
    'server_name': 'tower',
    'started_at': ago(const Duration(hours: 1)),
  };
  final direct = {
    ...rows[1],
    'id': 'f0a1b2c3-0003-4aaa-8bbb-000000000003',
    'server_id': TracearrFake.embyServerId,
    'server_name': 'tower',
    'username': 'Anna',
    'media_title': 'Sintel',
    'media_type': 'movie',
    'show_title': null,
    'season_number': null,
    'episode_number': null,
    'year': 2010,
    'state': 'playing',
    'progress_ms': 360000,
    'duration_ms': 888000,
    'started_at': ago(const Duration(hours: 1)),
    'device': 'Living Room TV',
    'player': 'Emby for Android TV',
    'product': 'Emby for Android TV',
    'platform': 'Android TV',
    'bitrate': 3100,
    'tmdb_id': 45,
    'media_id': 'd1d1d1d1-0000-4000-8000-0000000000c3',
    'show_media_id': null,
  };
  return TracearrStreams.fromJson({
    'data': [transcode, paused, direct],
    'summary': {
      'total': 3,
      'transcodes': 1,
      'audio_transcodes': 0,
      'direct_streams': 0,
      'direct_plays': 2,
      'total_bitrate': '14.8 Mbps',
    },
  });
}

/// The session the detail sheet opens on: the transcoding stream.
TracearrSession tracearrTranscodeSession() =>
    TracearrSession.live(_streams().streams.first);

/// A viewing from History, as recorded by a real Tracearr: the first row of
/// the recorded page.
TracearrSession tracearrRecordedSession() => TracearrSession.recorded(
  TracearrHistoryEntry.fromJson(
    (jsonFixtureMap('tracearr/history_page.json')['data'] as List).first
        as Map<String, dynamic>,
  ),
);

/// Live with the detail sheet open over it, the sheet drawn in place: a modal
/// on the root navigator is off the catalog's sheet, so the panel is the
/// app's own `AppBottomSheet` around the sheet's own body.
///
/// Laid out as the app opens it (`showTracearrSession`): a draggable sheet
/// whose body scrolls inside the sheet's own margin.
class TracearrSheetOver extends ConsumerStatefulWidget {
  const TracearrSheetOver({super.key, required this.behind, this.session});

  final Widget behind;

  /// The viewing; the Live transcode when null.
  final TracearrSession Function()? session;

  @override
  ConsumerState<TracearrSheetOver> createState() => _TracearrSheetOverState();
}

class _TracearrSheetOverState extends ConsumerState<TracearrSheetOver> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = (widget.session ?? tracearrTranscodeSession)();
    final behind = widget.behind;
    final title = tracearrMediaTitleOf(session.media);
    return Stack(
      fit: StackFit.expand,
      children: [
        behind,
        const ColoredBox(color: Colors.black54),
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.7,
            child: AppBottomSheet(
              title: title,
              subtitle: joinDisplayParts([
                tracearrPersonOf(session.person),
                session.device.name,
              ]),
              icon: Icons.play_circle_outline_rounded,
              headerTrailing: ServiceOverviewArt(posterUrl: null, title: title),
              scrollController: _scroll,
              bodyPadding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: SingleChildScrollView(
                controller: _scroll,
                child: TracearrSessionBody(
                  session: session,
                  onClose: () {},
                  host: context,
                  hostRef: ref,
                  onPersonPage: null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
