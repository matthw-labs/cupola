/// What Featured reads: the sources Continue watching, Arrived and Coming up
/// already read, and for the arrival it leads with, whether a media server
/// holds it.
library;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/domain/coming_up.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/data/last_known/featured_last_known.dart';
import 'package:cupola/features/home/data/last_known/lights_last_known.dart';
import 'package:cupola/features/home/data/last_known/my_requests_last_known.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_series.dart'
    show mediaNextEpisode;
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// Featured's slides: the first title in progress, the newest movie or
/// series that arrived, and a movie or an episode dated today, as their
/// sources answered.
///
/// A source that did not answer gives no slide and says nothing here: the
/// module that shows it whole (Continue watching, Arrived, Coming up) names
/// it. Every read is the one those modules hold, so Featured costs one more
/// read only: whether a media server holds the arrival, for its Play.
final featuredProvider = FutureProvider.autoDispose<List<FeaturedSlide>>((
  ref,
) async {
  final settings = ref.watch(currentSettingsProvider);
  bool any(List<ServiceKey> services) =>
      services.any(settings.isServiceConfigured);
  final players = any(mediaServers);
  final arrs = any(const [ServiceKey.radarr, ServiceKey.sonarr]);
  if (!players && !arrs) return const [];

  // Everything this build depends on is watched before the first wait: a
  // source that changes while it waits rebuilds it, and this build stops.
  final now = ref.watch(calendarClockProvider)();
  final since = ref.watch(arrivalsSinceProvider);
  Future<T?> settled<T>(Future<T> read) =>
      read.then<T?>((value) => value, onError: (Object _) => null);
  final (resume, arrivals, calendar) = await (
    players
        ? settled(ref.watch(homeResumeProvider.future))
        : Future<HomeResume?>.value(),
    arrs
        ? settled(ref.watch(servicesArrivalsProvider.future))
        : Future<ArrHistory?>.value(),
    arrs
        ? settled(ref.watch(libraryCalendarProvider.future))
        : Future<LibraryCalendar?>.value(),
  ).wait;
  if (!ref.mounted) return const [];

  // Every source it asked was silent: that is not "nothing to feature", it
  // is not knowing. Featured says no failure of its own (the modules below
  // name the servers), but a module with a last drawing keeps it over this.
  final silent = [
    if (players) resume == null || resume.coverage.everySourceFailed,
    if (arrs) arrivals == null || arrivals.coverage.everySourceFailed,
    if (arrs)
      calendar == null ||
          (calendar.answered.isEmpty && calendar.silent.isNotEmpty),
  ];
  if (silent.isNotEmpty && silent.every((source) => source)) {
    throw const FeaturedSourcesSilent();
  }

  final slides = featuredSlidesOf(
    resume: [
      for (final row in resume?.rows ?? const <ResumeRow>[])
        if (_resumeArt(ref, row) case final art?) FeaturedResume(row, art: art),
    ],
    arrivals: [
      for (final entry in featuredArrivalsOf(
        arrivals?.entries ?? const [],
        since: since,
      ))
        if (entry.backdropUrl.isNotEmpty)
          FeaturedArrival(entry, art: (url: entry.backdropUrl, headers: null)),
    ],
    today: [
      for (final event in featuredTodayOf(calendar?.events ?? const [], now))
        if (event.backdrop case final art? when art.url.isNotEmpty)
          FeaturedToday(event, art: art),
    ],
  );

  // The arrival plays where a media server says it holds it.
  final at = slides.indexWhere((slide) => slide is FeaturedArrival);
  if (players && at >= 0) {
    final arrival = slides[at] as FeaturedArrival;
    final play = await _playOf(ref, arrival.entry);
    if (!ref.mounted) return const [];
    if (play != null) {
      slides[at] = FeaturedArrival(arrival.entry, art: arrival.art, play: play);
    }
  }
  return slides;
}, retry: noProviderRetry);

/// Featured's read when every source it asked did not answer.
class FeaturedSourcesSilent implements Exception {
  const FeaturedSourcesSilent();

  @override
  String toString() => 'No source of Featured answered';
}

/// A row's wide artwork through its server, which owns the credential.
ImageSource? _resumeArt(Ref ref, ResumeRow row) {
  final path = row.item.backdropPath;
  if (path == null || path.isEmpty) return null;
  final server = ref.watch(
    streamBackendOf(row.service).clientFor(row.instanceId),
  );
  return server.imageFor(path, width: featuredArtWidth);
}

/// The first media server that holds [entry], and what its Play opens: the
/// movie, or a series' next episode (`mediaNextEpisode`), else the series.
/// The lookups are the Media page's own, so opening the title reads none
/// again.
Future<FeaturedPlay?> _playOf(Ref ref, ArrHistoryEntry entry) async {
  final tmdb = entry.tmdbId;
  if (tmdb == null || tmdb <= 0) return null;
  final key = entry.service == ServiceKey.radarr
      ? MediaKey.movie(tmdb)
      : MediaKey.tv(tmdb);
  final settings = ref.read(currentSettingsProvider);
  final servers = [
    for (final service in mediaServers)
      ...settings.configuredInstancesOf(service),
  ];
  final answers = await Future.wait([
    for (final server in servers)
      ref
          .watch(
            mediaStreamCopyProvider((key: key, connectionId: server.id)).future,
          )
          .then<MediaAnswer<MediaStreamCopy>?>(
            (answer) => answer,
            onError: (Object _) => null,
          ),
  ]);
  for (final (index, answer) in answers.indexed) {
    final copy = answer?.value;
    final item = copy?.item;
    if (copy == null || item == null) continue;
    final StreamItem opens = key.isMovie
        ? item
        : mediaNextEpisode(copy.episodes ?? const []) ?? item;
    return (
      service: servers[index].service,
      instanceId: servers[index].id,
      item: opens,
    );
  }
  return null;
}

/// Which slide is in front, and the pictures already drawn: a light is read
/// only off a picture the slide has drawn, from the same cache, so a server
/// that wants its credential for artwork still lights the room.
typedef FeaturedView = ({int index, Set<String> drawn});

/// What the pager has shown, kept while the Home is scrolled away from it.
final featuredViewProvider =
    NotifierProvider<FeaturedViewNotifier, FeaturedView>(
      FeaturedViewNotifier.new,
    );

class FeaturedViewNotifier extends Notifier<FeaturedView> {
  @override
  FeaturedView build() => (index: 0, drawn: const {});

  /// [index] is the slide in front now.
  void show(int index) {
    if (index != state.index) state = (index: index, drawn: state.drawn);
  }

  /// [url] has been drawn.
  void drawn(String url) {
    if (state.drawn.contains(url)) return;
    state = (index: state.index, drawn: {...state.drawn, url});
  }
}

/// The light of the artwork at [url], once a slide has drawn it; until then
/// the light it lit the room with last time (`keptTitleLight`); null for the
/// lamp.
///
/// The light read is kept for the next cold start, so the room and the
/// slide's lead action are lit from the first frame instead of turning from
/// ink to the title's colour half a second in.
final featuredLightProvider = Provider.autoDispose.family<TitleLight?, String>((
  ref,
  url,
) {
  final drawn = ref.watch(
    featuredViewProvider.select((view) => view.drawn.contains(url)),
  );
  if (drawn) {
    if (ref.watch(titleLightProvider(url)) case AsyncData(:final value)) {
      keepTitleLight(ref, url, value);
      return value;
    }
  }
  return keptTitleLight(ref, url);
});

/// The light a Home is lit by: on the operator's, the slide of Featured in
/// front; on the requester's, the title Ready to watch leads with; else the
/// lamp.
final featuredRoomLightProvider = Provider.autoDispose<Color?>(
  (ref) => ref.watch(featuredRoomProvider)?.light,
);

/// The whole light of a Home ([featuredRoomLightProvider]): its colours and,
/// once the slide in front has been read, its picture.
final featuredRoomProvider = Provider.autoDispose<TitleLight?>((ref) {
  final url = ref.watch(featuredRoomSourceProvider);
  if (url != null) return ref.watch(featuredLightProvider(url));
  // With nothing featured, the next thing out lights the room, as it lights
  // Coming up: a Home is never left to the lamp while a title leads it.
  final next = ref.watch(homeComingUpSourceProvider);
  return next == null ? null : ref.watch(titleLightProvider(next)).value;
});

/// The artwork that lights a Home, or null for the lamp; see
/// [featuredRoomLightProvider].
final featuredRoomSourceProvider = Provider.autoDispose<String?>((ref) {
  final shown = ref.watch(homeLayoutProvider).shown;
  if (ref.watch(shellAudienceProvider) == Audience.requester) {
    if (!shown.contains(HomeModule.readyToWatch)) return null;
    // The title Ready to watch draws: her answer's, or until it comes the
    // one it drew last, so the room keeps its light.
    return ref.watch(readyLeadProvider)?.art.url;
  }
  if (shown.contains(HomeModule.featured)) {
    // The drawn slides at a cold start, so the room is lit by the slide in
    // front from the first frame and does not change when the live ones come.
    final slides =
        ref.watch(featuredProvider).value ??
        ref.watch(homeLastKnownProvider(featuredLastKnown))?.value
            as List<FeaturedSlide>?;
    if (slides != null && slides.isNotEmpty) {
      final index = ref.watch(
        featuredViewProvider.select((view) => view.index),
      );
      return slides[index.clamp(0, slides.length - 1)].art.url;
    }
  }
  return null;
});

/// With nothing featured, the artwork of the next thing out, as Coming up
/// draws it (a public picture only); null for the lamp.
final homeComingUpSourceProvider = Provider.autoDispose<String?>((ref) {
  if (ref.watch(shellAudienceProvider) == Audience.requester) return null;
  if (!ref.watch(homeLayoutProvider).shown.contains(HomeModule.comingUp) ||
      !ref.watch(hasLibraryCalendarProvider)) {
    return null;
  }
  final events = ref.watch(libraryCalendarProvider).value?.events;
  if (events == null) return null;
  return [
    for (final event in comingUpOf(events, ref.watch(calendarClockProvider)()))
      if (event.poster case final poster?
          when poster.headers == null && poster.url.isNotEmpty)
        poster.url,
  ].firstOrNull;
});

/// Whether Featured moves on by itself: always in the app; off where a page
/// is settled frame by frame (the tests that pump a whole Home, the
/// catalog), as the Home's thirty-second poll is.
final featuredAdvancesProvider = Provider<bool>((ref) => true);
