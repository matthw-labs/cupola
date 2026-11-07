import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/models/arr_media_file.dart';
import 'package:cupola/core/status/media_action.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_videos_button.dart';
import 'package:cupola/features/bazarr/presentation/widgets/bazarr_detail_sections.dart';
import 'package:cupola/features/media/presentation/media_episode_sheet.dart';
import 'package:cupola/features/media/presentation/media_episodes_graph.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_web_url.dart';
import 'package:cupola/features/stream/presentation/play_with.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_cast_list.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/media/domain/media_collection.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/seerr_request_words.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/discover/presentation/catalog_title_actions.dart'
    show seerrSendsToProvider;
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_lead.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/media/domain/media_row_view.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/media/domain/media_removal.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_watched_by.dart';
import 'package:cupola/features/media/presentation/media_series_manage.dart';
import 'package:cupola/features/media/presentation/media_series_sections.dart';
import 'package:cupola/features/media/presentation/media_add_sheet.dart';
import 'package:cupola/features/media/presentation/media_copy_panel_card.dart';
import 'package:cupola/features/media/presentation/media_decision_card.dart';
import 'package:cupola/features/media/presentation/media_facts_sections.dart';
import 'package:cupola/features/media/domain/media_facts.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/media/presentation/media_identity.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/operator_adds_via_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/media/presentation/media_manage_parts.dart';
import 'package:cupola/features/media/presentation/media_manage_summaries.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The canonical Media page: one title, the same page from every entry
/// point.
///
/// Four layers, top to bottom: who the title is (artwork, title, scores), the
/// one action that leads, what every connection holds ("On your server"),
/// and the operator's sections, closed. [focus] is the connection the page
/// was opened from: its copy leads when it needs something.
class MediaPage extends ConsumerStatefulWidget {
  const MediaPage({
    super.key,
    required this.mediaKey,
    this.focus,
    this.season,
    this.heroTag,
    this.posterUrl,
  });

  final MediaKey mediaKey;
  final String? focus;

  /// The season of a series the episodes open on, when the page was opened
  /// from a season or an episode (`?season=`; 0 is the specials). A season
  /// the series does not have asks for nothing.
  final int? season;

  /// The tag of the tile the page was opened from: its poster flies here.
  final String? heroTag;

  /// The poster that tile drew, standing in until the page has read who the
  /// title is, so the flight lands on a picture rather than a shimmer.
  final String? posterUrl;

  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage> {
  /// Where Manage scrolls to.
  final _manageKey = GlobalKey();

  /// Watchlist as the user just set it, and when: it stands until Seerr
  /// answers after that.
  ({bool on, DateTime at})? _watchlisted;

  /// The artwork the page has drawn: the title light is read from one of
  /// these only.
  final _drawn = <String>{};

  void _artDrawn(String url) {
    if (_drawn.contains(url)) return;
    // After the frame that drew it: a setState inside an image builder would
    // rebuild the tree that is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _drawn.add(url));
    });
  }

  MediaKey get mediaKey => widget.mediaKey;
  String? get focus => widget.focus;

  /// Plays [lead] at its item, in the app the viewer chooses for it.
  Future<void> _play(MediaLeadPlay lead) {
    final item = lead.episode ?? lead.item;
    return _playOn(lead.server, item.id, item.title);
  }

  /// Opens the item [itemId] on [server]: its own app when the viewer has
  /// several to choose from (`playWith`), its web client otherwise.
  Future<void> _playOn(
    ServiceInstance server,
    String itemId,
    String title,
  ) async {
    final machineId = switch (server.service) {
      ServiceKey.plex =>
        ref
            .read(plexCapabilitiesForProvider(server.id))
            .value
            ?.machineIdentifier,
      // Emby's link names the server too, and works when it does not answer.
      ServiceKey.emby => await _embyServerId(server.id),
      _ => null,
    };
    if (!mounted) return;
    // The web client at the address the server is reached at now.
    final target = streamItemWebUrl(
      service: server.service,
      baseUrl: ref.read(connectionReachProvider(server.id))?.url ?? '',
      itemId: itemId,
      serverId: machineId,
    );
    return playWith(
      context,
      ref,
      server: server,
      itemId: itemId,
      title: title,
      webUrl: target,
    );
  }

  Future<String?> _embyServerId(String instanceId) async {
    try {
      return await ref.read(embyServerIdProvider(instanceId).future);
    } catch (_) {
      return null;
    }
  }

  /// The Seerr "More like this" is read through: the first one set up, while
  /// the title has a TMDB id.
  String? _recommender(SettingsModel settings) {
    if (mediaKey.tmdbId == null) return null;
    return settings
        .instancesOf(ServiceKey.seerr)
        .where((instance) => instance.isConfigured)
        .firstOrNull
        ?.id;
  }

  /// Where [view]'s one way forward leads, for [row]: a setup form, the
  /// connection asked again, or its own form for the remedy a failure names.
  VoidCallback? _wayOf(
    MediaRow row,
    MediaRowView view, {
    required List<MediaRow> rows,
    required MediaIdentity? identity,
    required TitleLight? light,
  }) => switch (view.way) {
    null => null,
    MediaRowWay.addCopy => () => _add(
      MediaLeadAdd(row.service),
      [row],
      identity,
      light,
      retry: rows,
    ),
    MediaRowWay.setUp ||
    MediaRowWay.add => () => context.push(ServiceRoutes.setUp(row.service)),
    MediaRowWay.retry => () => retryMediaRow(ref, mediaKey, row),
    MediaRowWay.fix => () => context.push(
      ServiceRoutes.settingsForConnection(row.service, view.connectionId ?? ''),
    ),
    MediaRowWay.review => () async {
      await context.push(
        manualImportLocation(
          manualImportReviewPath,
          row.service,
          targetId: view.targetId,
          instanceId: view.connectionId,
        ),
      );
      if (mounted) retryMediaRow(ref, mediaKey, row);
    },
  };

  /// Adds the title to the Radarr or Sonarr chosen in the sheet, then reads
  /// each of them again: the row and the lead change with the answer.
  ///
  /// [rows] are the connections the sheet offers; [retry], the rows read
  /// again after, when they are more than those.
  Future<void> _add(
    MediaLeadAdd lead,
    List<MediaRow> rows,
    MediaIdentity? identity,
    TitleLight? light, {
    List<MediaRow>? retry,
    _Request? requestInstead,
  }) async {
    final tmdbId = mediaKey.tmdbId;
    // Sonarr knows a series by TVDB's id; TMDB's stands in without it.
    final tvdbId = mediaKey.isMovie
        ? null
        : ref.read(mediaTvdbIdProvider(mediaKey)).value;
    final arrs = [
      for (final row in rows)
        if (row is MediaConnectionRow && row.service == lead.arr) row,
    ];
    if ((tmdbId ?? tvdbId) == null || arrs.isEmpty) return;
    final settings = ref.read(currentSettingsProvider);
    String name(ServiceInstance connection) =>
        settings.connectionTitle(connection.id, connection.service);
    final added = await showMediaAddSheet(
      context,
      arr: lead.arr,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      connections: [for (final row in arrs) row.connection],
      name: name,
      title: identity?.title ?? '',
      year: identity?.year,
      light: light,
      alternative: requestInstead == null
          ? null
          : (
              label: 'Request through Seerr instead',
              onTap: () =>
                  _request(requestInstead, identity, rows, light: light),
            ),
    );
    if (added == null || !mounted) return;
    SnackBarHelper.success(context, 'Added to ${name(added)}');
    for (final row in retry ?? arrs) {
      if (row is MediaConnectionRow && row.service == lead.arr) {
        retryMediaRow(ref, mediaKey, row);
      }
    }
  }

  /// What Request says and may do through [lead]'s Seerr: the title's state
  /// there, read as that Seerr numbers it, and what this account may ask.
  /// Null until that Seerr has answered.
  _Request? _requestOf(MediaLeadRequest lead, List<MediaRow> rows) {
    final seerr = lead.seerr;
    MediaSeerrRecord? record;
    for (final row in rows) {
      if (row case MediaConnectionRow(
        :final connection,
        reading: MediaReadingAnswered(:final answer),
      ) when connection.id == seerr.id) {
        if (answer.value case final MediaSeerrRecord answered) {
          record = answered;
        }
      }
    }
    if (record == null) return null;
    final kind = mediaKey.isMovie ? SeerrMediaKind.movie : SeerrMediaKind.tv;
    final roleGate = ref.watch(roleGateProvider(seerr.id));
    // An account is offered 4K when it may ask for it; the key, when Seerr
    // has a 4K server for the kind.
    final has4k = roleGate.grant?.isApiKey == false
        ? roleGate.offers4k(kind)
        : record.arrServers?.any((server) => server.is4k) ?? false;
    final gate = seerrRequestGate(
      record.mediaInfo,
      isMovie: mediaKey.isMovie,
      seasons: mediaKey.isMovie
          ? const []
          : DiscoverDetailViewModel.of(record.details).seasons,
      numbering: ref.watch(mediaSeerrNumberingProvider(seerr.id)).value,
      has4kServer: has4k,
    );
    final arr = mediaKey.isMovie ? ServiceKey.radarr : ServiceKey.sonarr;
    final words = seerrRequestWords(
      gate,
      namesSeerr: roleGate.namesService(ServiceKey.seerr),
      namesArr: roleGate.namesService(arr),
      arrName: arr.title,
      arrTracks: _arrTracks(arr, rows),
    );
    // On the server by Seerr's word, with Seerr's link to it: watched there,
    // in the player Seerr is set up with.
    final link =
        stringOrNull(record.mediaInfo?['mediaUrl']) ??
        stringOrNull(record.mediaInfo?['mediaUrl4k']);
    final watchAt = gate.state == SeerrRequestState.available
        ? Uri.tryParse(link ?? '')
        : null;
    // The key's gate knows no server: its public settings name the player.
    final player = watchAt == null
        ? null
        : roleGate.server?.mediaServer ??
              ref.watch(seerrServerFactsProvider(seerr.id)).value?.mediaServer;
    return (
      gate: gate,
      words: words,
      verdict: words.open ? roleGate.requestAction(kind) : const Live(),
      // Seerr's field is server-controlled: `hasScheme` is true for
      // `intent:`, `file:` and `javascript:` too, and every other server URL
      // in the app goes through this allowlist before the OS sees it.
      watch: watchAt == null || !UrlUtils.isLaunchableWebUri(watchAt)
          ? null
          : (label: SeerrMediaServer.watchLabel(player), url: watchAt),
    );
  }

  /// Whether [arr] tracks the title, read from its own rows: true when any
  /// copy holds it, false when every copy answered without it, null while one
  /// has not answered.
  bool? _arrTracks(ServiceKey arr, List<MediaRow> rows) {
    var answered = false;
    for (final row in rows) {
      if (row is! MediaConnectionRow || row.service != arr) continue;
      if (row.reading case MediaReadingAnswered(:final answer)) {
        switch (answer.value) {
          case MediaRadarrCopy(movie: _?) || MediaSonarrCopy(series: _?):
            return true;
          case MediaRadarrCopy() || MediaSonarrCopy():
            answered = true;
          default:
            return null;
        }
      } else {
        return null;
      }
    }
    return answered ? false : null;
  }

  /// Opens Seerr's link to the title in its player.
  Future<void> _watch(Uri url) async {
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackBarHelper.error(context, 'Could not open it');
    }
  }

  /// Opens the request sheet, then reads Seerr again.
  void _request(
    _Request request,
    MediaIdentity? identity,
    List<MediaRow> rows, {
    TitleLight? light,
    ServiceKey? addInstead,
  }) {
    final tmdbId = mediaKey.tmdbId;
    if (tmdbId == null) return;
    AppBottomSheet.show<void>(
      context: context,
      title:
          'Request ${identity?.title ?? (mediaKey.isMovie ? 'movie' : 'series')}',
      subtitle: identity?.metaLine,
      // Closed as its sibling the add sheet is.
      showClose: true,
      builder: (_) => RequestBottomSheet(
        mediaId: tmdbId,
        mediaType: mediaKey.isMovie ? 'movie' : 'tv',
        copies: request.gate.copies,
        title: identity?.title,
        alternative: addInstead == null
            ? null
            : (
                label: 'Add to ${addInstead.title} instead',
                onTap: () =>
                    _add(MediaLeadAdd(addInstead), rows, identity, light),
              ),
        onRequestComplete: () {
          if (!mounted) return;
          SnackBarHelper.success(context, 'Request submitted');
          // Seerr passes an approved request on to the arr: its rows are
          // read again too, so the line under Requested and the arr's row say
          // the same thing.
          for (final row in rows) {
            if (row.service == ServiceKey.seerr ||
                row.service ==
                    (mediaKey.isMovie
                        ? ServiceKey.radarr
                        : ServiceKey.sonarr)) {
              retryMediaRow(ref, mediaKey, row);
            }
          }
        },
      ),
    );
  }

  /// Whether the title is on the watchlist of the user [seerrId] acts as,
  /// as that Seerr answered; null until it has.
  static ({bool on, DateTime at})? _onWatchlist(
    List<MediaRow> rows,
    String seerrId,
  ) {
    for (final row in rows) {
      if (row case MediaConnectionRow(
        :final connection,
        reading: MediaReadingAnswered(:final answer),
      ) when connection.id == seerrId) {
        if (answer.value case final MediaSeerrRecord record) {
          return (on: record.details['onUserWatchlist'] == true, at: answer.at);
        }
      }
    }
    return null;
  }

  /// Puts the title on that watchlist or takes it off: shown at once, then
  /// written, then Seerr read again; put back when the write failed.
  Future<void> _toggleWatchlist(
    String seerrId,
    bool on,
    MediaIdentity? identity,
    List<MediaRow> rows,
  ) async {
    final tmdbId = mediaKey.tmdbId;
    if (tmdbId == null) return;
    final mediaType = mediaKey.isMovie ? 'movie' : 'tv';
    setState(() => _watchlisted = (on: !on, at: DateTime.now()));
    final seerr = ref.read(seerrServiceForProvider(seerrId));
    try {
      if (on) {
        await seerr.removeFromWatchlist(tmdbId: tmdbId, mediaType: mediaType);
      } else {
        await seerr.addToWatchlist(
          tmdbId: tmdbId,
          mediaType: mediaType,
          title: identity?.title ?? '',
        );
      }
      if (!mounted) return;
      SnackBarHelper.success(
        context,
        on ? 'Taken off your watchlist' : 'On your watchlist',
      );
      for (final row in rows) {
        if (row.service == ServiceKey.seerr) retryMediaRow(ref, mediaKey, row);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _watchlisted = null);
      SnackBarHelper.error(
        context,
        on
            ? 'Could not take it off your watchlist'
            : 'Could not put it on your watchlist',
        detail: error,
      );
    }
  }

  /// The film [connectionId]'s Radarr holds, when it answered with one.
  static RadarrMovie? _radarrMovieOf(List<MediaRow> rows, String connectionId) {
    for (final row in rows) {
      if (row case MediaConnectionRow(
        :final connection,
        reading: MediaReadingAnswered(:final answer),
      ) when connection.id == connectionId) {
        if (answer.value case MediaRadarrCopy(:final movie?)) return movie;
      }
    }
    return null;
  }

  /// Reads every Radarr and Sonarr again, after something here changed what
  /// they hold.
  void _readArrsAgain(List<MediaRow> rows) {
    for (final row in rows) {
      if (row.service == ServiceKey.radarr ||
          row.service == ServiceKey.sonarr) {
        retryMediaRow(ref, mediaKey, row);
      }
    }
  }

  /// The episodes Bazarr follows for a series, and the Sonarr whose copy
  /// they are; null without them.
  ({String arr, List<BazarrEpisode> episodes})? _bazarrEpisodesOf(
    List<MediaRow> rows,
  ) {
    for (final row in rows) {
      if (row case MediaConnectionRow(
        reading: MediaReadingAnswered(:final answer),
      )) {
        if (answer.value case MediaBazarrCopy(
          :final arrConnectionId,
          :final episodes?,
        )) {
          return (arr: arrConnectionId, episodes: episodes);
        }
      }
    }
    return null;
  }

  /// Brings Manage into view.
  ///
  /// A long series builds its seasons first, and the list builds Manage only
  /// once it scrolls near it: until it has, the page runs down a screen at a
  /// time, then settles on the heading. A key with no context was a tap that
  /// did nothing (Manage on Grey's Anatomy, 11/10).
  Future<void> _toManage() async {
    final still = MediaQuery.disableAnimationsOf(context);
    final controller = PrimaryScrollController.maybeOf(context);
    for (var step = 0; _manageKey.currentContext == null && step < 60; step++) {
      // One list: the page's own (a pane beside a list keeps to itself).
      if (controller == null || controller.positions.length != 1) return;
      final position = controller.position;
      if (position.pixels >= position.maxScrollExtent) return;
      final next = math.min(
        position.pixels + position.viewportDimension,
        position.maxScrollExtent,
      );
      if (still) {
        position.jumpTo(next);
        await WidgetsBinding.instance.endOfFrame;
      } else {
        await position.animateTo(
          next,
          duration: const Duration(milliseconds: 120),
          curve: Curves.linear,
        );
      }
      if (!mounted) return;
    }
    final target = _manageKey.currentContext;
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      duration: still ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(mediaRowsProvider(mediaKey));
    final audience = ref.watch(audienceProvider);
    final settings = ref.watch(currentSettingsProvider);
    final identity = MediaIdentity.of(rows);
    // The scores are Seerr's and the arrs': with neither set up, four dashes
    // would promise figures no source here can give.
    final scored = rows.any(
      (row) =>
          row is MediaConnectionRow &&
          const {
            ServiceKey.seerr,
            ServiceKey.radarr,
            ServiceKey.sonarr,
          }.contains(row.service),
    );
    // The operator's choice of how a title nobody holds is added, and whether
    // the Seerr that answered may take the request for it now. Read for the
    // operator only, and only once a Seerr has answered: until then the lead
    // has nothing to wait on that Seerr could change.
    final addsVia = audience == Audience.operator
        ? ref.watch(operatorAddsViaProvider)
        : OperatorAddsVia.seerr;
    final seerrRows = rows
        .whereType<MediaConnectionRow<MediaSeerrRecord>>()
        .toList(growable: false);
    final askable =
        audience == Audience.operator &&
        seerrRows.any((row) => row.reading is MediaReadingAnswered);
    final seerrKind = mediaKey.isMovie
        ? SeerrMediaKind.movie
        : SeerrMediaKind.tv;
    final seerrArr = mediaKey.isMovie ? ServiceKey.radarr : ServiceKey.sonarr;
    final sendsTo = askable ? ref.watch(seerrSendsToProvider(seerrArr)) : null;
    final mayAsk = {
      for (final row in seerrRows)
        row.connection.id:
            ref
                    .watch(roleGateProvider(row.connection.id))
                    .requestAction(seerrKind)
                is Live,
    };
    bool? Function(ServiceInstance seerr)? seerrMayRequest;
    if (askable) {
      seerrMayRequest = (seerr) {
        if (!(mayAsk[seerr.id] ?? false)) return false;
        return switch (sendsTo) {
          AsyncData(value: final sends) => sends,
          AsyncError() => false,
          _ => null,
        };
      };
    }
    final lead = resolveMediaLead(
      rows,
      audience: audience,
      focus: focus,
      addsVia: addsVia,
      seerrMayRequest: seerrMayRequest,
    );
    // The requester reads the players' rows only, and none that says how to
    // set one up.
    final shown = [
      for (final row in rows)
        if (audience == Audience.operator ||
            (row is MediaConnectionRow && row.service.isMediaServer))
          row,
    ];
    // The one image that lights the room: the backdrop, else the poster. Until
    // it is read, and for artwork with too little chroma, the lamp.
    // It is read once the page has drawn that picture: it comes from the same
    // cache then, and a picture that never arrives leaves the lamp on.
    final lightSource = identity?.backdropUrl ?? identity?.posterUrl;
    final lit = _drawn.contains(lightSource) ? lightSource : null;
    final light = lit == null ? null : ref.watch(titleLightProvider(lit)).value;
    final now = DateTime.now();
    // Each row with what it draws: a row with nothing to show (Bazarr's,
    // which Manage carries) is not counted among the services either.
    final drawn = [
      for (final row in shown)
        (
          row,
          mediaRowViews(
            row,
            title: (connection) =>
                settings.connectionTitle(connection.id, connection.service),
            now: now,
            rows: rows,
          ),
        ),
    ];
    final views = [
      for (final (row, rowViews) in drawn)
        for (final view in rowViews)
          _ServerRow(
            view,
            onTap: _wayOf(
              row,
              view,
              rows: rows,
              identity: identity,
              light: light,
            ),
          ),
    ];
    // The title's downloads, read from the queue. Nothing while the queue has
    // not answered, and nothing once it failed. The copy panel that leads
    // already speaks for its own download, so that one is not listed twice:
    // its panel opens it instead.
    // The queue is the operator's: a requester reads none of the arrs, so it is
    // not even asked.
    final queueRead = audience == Audience.operator
        ? ref.watch(servicesQueueProvider)
        : null;
    final queued = queueRead == null || queueRead.hasError
        ? const <ServiceQueueItem>[]
        : queueRead.value?.items ?? const <ServiceQueueItem>[];
    final panelCopy = lead is MediaLeadCopy
        ? _radarrMovieOf(rows, lead.connection.id)
        : null;
    bool isPanelDownload(ServiceQueueItem item) =>
        panelCopy != null &&
        lead is MediaLeadCopy &&
        item.service == ServiceKey.radarr &&
        item.instanceId == lead.connection.id &&
        item.mediaId == panelCopy.id;
    final panelDownload = queued.where(isPanelDownload).firstOrNull;
    final titleDownloads = [
      for (final item in _titleDownloads(rows, queued))
        if (!isPanelDownload(item)) item,
    ];
    final request = lead is MediaLeadRequest ? _requestOf(lead, rows) : null;
    // The request the add sheet may offer instead, read here, where the page
    // watches Seerr.
    final addRequest = lead is MediaLeadAdd && lead.alternative != null
        ? _requestOf(MediaLeadRequest(lead.alternative!), rows)
        : null;
    // A series: its seasons and episodes, and the next one to air.
    final seasons = mediaKey.isMovie
        ? const <MediaSeason>[]
        : mediaSeasonsOf(rows, audience: audience, now: now, focus: focus);
    final nextAiring = mediaKey.isMovie
        ? null
        : mediaNextAiringOf(rows, now: now);
    // The graph reads TMDB's votes through the first Seerr that answered.
    final graphSource = mediaKey.isMovie ? null : _graphSource(rows);
    final region = ref.watch(regionProvider);
    // The requests that wait on the operator, answered from here: in the
    // lead's place while the title is on no server, under the lead otherwise.
    final decisions = audience == Audience.operator
        ? [
            for (final pending in mediaPendingRequests(rows))
              if (ref
                  .watch(roleGateProvider(pending.seerr.id))
                  .operatorAction(SeerrAbility.approve)
                  .isDrawn)
                pending,
          ]
        : const <MediaPendingRequest>[];
    final decisionLeads =
        decisions.isNotEmpty &&
        switch (lead) {
          MediaLeadAdd() ||
          MediaLeadRequest() ||
          MediaLeadTrailer() ||
          MediaLeadNone() => true,
          _ => false,
        };
    // Watchlist is Seerr's, kept for the user the connection acts as: no
    // Seerr, no Watchlist.
    final watchlistSeerr = _recommender(settings);
    final answeredWatchlist = watchlistSeerr == null
        ? null
        : _onWatchlist(rows, watchlistSeerr);
    final chosen = _watchlisted;
    final watchlisted =
        chosen != null &&
            (answeredWatchlist == null ||
                !answeredWatchlist.at.isAfter(chosen.at))
        ? chosen.on
        : answeredWatchlist?.on;
    // Under the buttons, what a request means now: why there is none to make,
    // what one would add, or for the requester, that the title is not there.
    final requestLine =
        request == null || request.watch != null || decisions.isNotEmpty
        ? null
        : request.words.reason ??
              request.verdict.reason ??
              request.words.adds ??
              (audience == Audience.requester
                  ? 'Not on the server yet.'
                  : null);
    // Manage is the operator's, and only when there is something to manage.
    final manage = audience == Audience.operator
        ? _manage(rows, settings)
        : const <Widget>[];
    final room = CupolaRoom.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final waiting = rows.any(
      (row) => row is MediaConnectionRow && row.reading is MediaReadingWaiting,
    );
    // Nobody can say who the title is while the Seerr that would did not
    // answer: a session that ended makes the page the way to sign in again,
    // as every Seerr page is; for the requester, who reads no rows, any
    // failure is the page, in her words.
    final silentSeerr = identity != null || waiting
        ? null
        : rows
              .whereType<MediaConnectionRow<MediaSeerrRecord>>()
              .where(
                (row) => switch (row.reading) {
                  MediaReadingFailed(:final failure) =>
                    failure == ServiceFailureReason.sessionEnded ||
                        audience == Audience.requester,
                  _ => false,
                },
              )
              .firstOrNull;
    final silence = switch (silentSeerr?.reading) {
      MediaReadingFailed(:final failure, :final gateway) => ClassifiedFailure(
        failure,
        gateway: gateway,
      ),
      _ => null,
    };

    final page = LayoutBuilder(
      builder: (context, box) {
        // The page's own width, not the window's: in a tablet's detail
        // pane it is a phone's column, full screen it takes two tracks.
        final column = (box.maxWidth - 2 * AppSpacing.lg).clamp(
          0.0,
          AppBreakpoints.contentWell,
        );
        final gutter = (box.maxWidth - column) / 2;
        final head = <Widget>[
          // The back plate floats here, pinned (`MediaPinnedPlates`).
          const SizedBox(height: MediaPinnedPlates.reserve),
          const SizedBox(height: AppSpacing.md),
          _Hero(
            onArtDrawn: _artDrawn,
            backdropHeight: (column / 2.6).clamp(214, 420),
            identity: identity,
            kind: mediaKey.kind,
            heroTag: widget.heroTag,
            posterUrl: widget.posterUrl,
            waiting: identity == null && waiting,
            marks: mediaFormatMarks(rows),
            light: light,
          ),
        ];
        final act = <Widget>[
          if (scored) ...[
            const SizedBox(height: AppSpacing.lg),
            _Scores(
              scores: mediaScoresOf(rows, identity),
              showMetacritic: audience == Audience.operator,
              series: !mediaKey.isMovie,
            ),
          ],
          const SizedBox(height: AppSpacing.slabY),
          // A Radarr copy that needs something says so where the lead
          // stands, and what can be done.
          if (lead case MediaLeadCopy(
            :final connection,
            :final status,
          ) when _radarrMovieOf(rows, connection.id) != null)
            MediaCopyPanelCard(
              connection: connection,
              name: settings.connectionTitle(connection.id, connection.service),
              movie: _radarrMovieOf(rows, connection.id)!,
              status: status,
              onChanged: () => _readArrsAgain(rows),
              onOpenDownload: panelDownload == null
                  ? null
                  : () => context.openDownload(panelDownload),
            )
          else
            _LeadBar(
              lead: lead,
              light: light,
              onPlay: _play,
              onTrailer: identity?.videos.isNotEmpty ?? false
                  ? () => DiscoverVideosButton.show(context, identity!.videos)
                  : null,
              onManage: _toManage,
              watchlist: watchlistSeerr == null || watchlisted == null
                  ? null
                  : (
                      on: watchlisted,
                      onTap: () => _toggleWatchlist(
                        watchlistSeerr,
                        watchlisted,
                        identity,
                        rows,
                      ),
                    ),
              request: request,
              onRequest: request == null
                  ? null
                  : () => _request(
                      request,
                      identity,
                      rows,
                      light: light,
                      addInstead: lead is MediaLeadRequest
                          ? lead.alternative
                          : null,
                    ),
              onWatch: request?.watch == null
                  ? null
                  : () => _watch(request!.watch!.url),
              onWatchAt: _watch,
              onAdd: (lead) =>
                  _add(lead, rows, identity, light, requestInstead: addRequest),
              hasTrailer: identity?.videos.isNotEmpty ?? false,
              showManage: manage.isNotEmpty,
              primary: decisionLeads
                  ? _decisionCards(
                      decisions,
                      title: identity?.title ?? '',
                      leads: true,
                      light: light,
                      rows: rows,
                    )
                  : null,
              serverName: (lead) =>
                  settings.connectionTitle(lead.server.id, lead.server.service),
            ),
          // A title that is downloading leads to its download's own page, right
          // under the lead.
          if (titleDownloads.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _TitleDownloads(items: titleDownloads),
          ],
          if (decisions.isNotEmpty && !decisionLeads) ...[
            const SizedBox(height: AppSpacing.md),
            _decisionCards(
              decisions,
              title: identity?.title ?? '',
              leads: false,
              light: light,
              rows: rows,
            ),
          ],
          if (nextAiring != null) ...[
            const SizedBox(height: AppSpacing.md),
            MediaNextAiringCard(
              next: nextAiring,
              now: now,
              operator: audience == Audience.operator,
            ),
          ],
          if (requestLine != null) ...[
            const SizedBox(height: AppSpacing.md),
            _StateLine(
              requestLine,
              tone: switch (request?.gate.state) {
                SeerrRequestState.waitingForApproval ||
                SeerrRequestState.onItsWay => StatusTone.info,
                SeerrRequestState.failed => StatusTone.warning,
                SeerrRequestState.available => StatusTone.success,
                SeerrRequestState.blocklisted => StatusTone.neutral,
                // Not there yet: the backlog's ring.
                _ => null,
              },
            ),
          ],
        ];
        final serve = <Widget>[
          // The requester's line already says the title is not there, or
          // where her request stands: the players' rows would repeat it.
          if (views.isNotEmpty &&
              !(audience == Audience.requester && requestLine != null)) ...[
            MediaHeading(
              'On your server',
              trailing: _servicesCount([
                for (final (row, rowViews) in drawn)
                  if (rowViews.isNotEmpty) row,
              ]),
            ),
            MediaGroup(children: views),
          ],
          if (graphSource case (:final seerr, :final tvId, :final numbers))
            MediaEpisodesGraphPanel(
              connectionId: seerr,
              tvId: tvId,
              seasons: numbers,
              light: light,
              upcoming: switch (nextAiring) {
                final next? when next.premiere => (
                  season: next.season,
                  day: mediaAiringDay(next, now),
                ),
                _ => null,
              },
              onOpen: () => _openGraph(
                seerr: seerr,
                tvId: tvId,
                numbers: numbers,
                seasons: seasons,
                rows: rows,
                title: identity?.title ?? '',
                light: light,
                operator: audience == Audience.operator,
              ),
            ),
          if (seasons.isNotEmpty) ...[
            const MediaHeading('Episodes'),
            MediaEpisodes(
              key: ValueKey(('episodes', mediaKey)),
              seasons: seasons,
              initialSeason: _initialSeason(lead, seasons),
              onSearchMissing: audience == Audience.operator
                  ? (season) => _searchMissing(season, rows)
                  : null,
              onOpen: (episode) => _openEpisode(
                episode,
                seasons: seasons,
                rows: rows,
                title: identity?.title ?? '',
                light: light,
                operator: audience == Audience.operator,
              ),
            ),
          ],
          ...manage,
          // The operator's, and only where Tracearr answered.
          if (audience == Audience.operator) MediaWatchedBy(mediaKey: mediaKey),
          if (mediaWatchProvidersOf(rows, region) case final providers?) ...[
            MediaHeading('Where to watch', trailing: regionName(region)),
            MediaWatchProviders(providers: providers),
          ],
        ];
        final reference = <Widget>[
          if ((identity?.overview ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.section),
            Text(
              identity!.overview,
              style: AppType.body.copyWith(color: room.ink),
            ),
          ],
          if ((identity?.creditsLine ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              identity!.creditsLine,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ],
          if (mediaKey.isMovie)
            if (mediaReleasesOf(rows, region) case final releases?) ...[
              MediaHeading(
                'Release dates',
                trailing: switch (releases.region) {
                  final code? => regionName(code),
                  null => null,
                },
              ),
              MediaReleaseDates(releases: releases),
            ],
          if (identity?.cast.isNotEmpty ?? false) ...[
            const MediaHeading('Cast'),
            DiscoverCastList(cast: identity!.cast, padding: EdgeInsets.zero),
          ],
          if (identity?.collection case final collection?) ...[
            const SizedBox(height: AppSpacing.section),
            _CollectionBand(
              collection: collection,
              held: switch (_recommender(settings)) {
                final seerr? =>
                  ref
                      .watch(
                        mediaCollectionHeldProvider((
                          connectionId: seerr,
                          collectionId: collection.id,
                        )),
                      )
                      .value,
                null => null,
              },
            ),
          ],
        ];
        final recommendations = switch (_recommender(settings)) {
          final seerr? => ref.watch(
            mediaRecommendationsProvider((key: mediaKey, connectionId: seerr)),
          ),
          null => null,
        };
        final more = <Widget>[
          // A Seerr that did not answer says so once, on its row or as
          // the page: More like this steps aside rather than say it again.
          if (recommendations != null && !recommendations.hasError) ...[
            const SizedBox(height: AppSpacing.section),
            // Across the page, its first poster on the column's line.
            DiscoverCarousel(
              title: 'More like this',
              sectionId: 'media-more-like-this',
              inset: gutter,
              forcedMediaType: mediaKey.isMovie ? 'movie' : 'tv',
              items: recommendations,
            ),
          ],
        ];
        if ((silentSeerr, silence) case (final row?, final failure?)) {
          return MediaPinnedPlates(
            inset: gutter,
            child: CustomScrollView(
              primary: true,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    top + AppSpacing.md,
                    gutter,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(child: head.first),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppErrorState(
                    service: ServiceKey.seerr,
                    instanceId: row.connection.id,
                    error: failure,
                    onRetry: failureRetryHelps(failure.reason)
                        ? () => retryMediaRow(ref, mediaKey, row)
                        : null,
                  ),
                ),
              ],
            ),
          );
        }
        // Clear of the floating bar, which grows with the reading size;
        // where there is none, a margin.
        final bottom = math.max(
          AppSpacing.xxxl,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        );
        // The route's primary list, on every platform: Manage and a tap on
        // the status bar both find it there.
        return MediaPinnedPlates(
          inset: gutter,
          child: CustomScrollView(
            primary: true,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  top + AppSpacing.md,
                  gutter,
                  more.isEmpty ? bottom : 0,
                ),
                sliver: SliverList.list(
                  children: [
                    ...head,
                    if (box.maxWidth >= AppBreakpoints.touchRail)
                      // Two tracks: who the title is and what to do with it
                      // on the left, the servers and Manage beside it.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [...act, ...reference],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xl),
                          SizedBox(
                            width: _sideTrack,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: serve,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      ...act,
                      ...serve,
                      ...reference,
                    ],
                  ],
                ),
              ),
              if (more.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.only(bottom: bottom),
                  sliver: SliverList.list(children: more),
                ),
            ],
          ),
        );
      },
    );
    return MediaRoom(light: light, child: page);
  }

  /// The season the episodes open on: the one the page was asked for (a
  /// season or an episode opened it) when the series has it, else the one
  /// Play would continue, else the latest with an episode that has aired,
  /// else the first.
  int _initialSeason(MediaLead lead, List<MediaSeason> seasons) {
    final asked = widget.season;
    if (asked != null && seasons.any((season) => season.number == asked)) {
      return asked;
    }
    if (lead case MediaLeadPlay(
      episode: StreamItem(:final seasonNumber?),
    ) when seasons.any((season) => season.number == seasonNumber)) {
      return seasonNumber;
    }
    final aired = [
      for (final season in seasons)
        if (season.number > 0 &&
            season.episodes.any(
              (episode) => episode.state != StateWord.notAired.label,
            ))
          season.number,
    ];
    return aired.lastOrNull ?? seasons.first.number;
  }

  /// The Seerr whose record names the series' seasons, the series' TMDB id,
  /// and the seasons TMDB lists episodes for; null without one.
  ({String seerr, int tvId, List<int> numbers})? _graphSource(
    List<MediaRow> rows,
  ) {
    final tvId = mediaKey.tmdbId;
    if (tvId == null) return null;
    for (final row in rows) {
      if (row case MediaConnectionRow(
        :final connection,
        reading: MediaReadingAnswered(:final answer),
      ) when answer.value is MediaSeerrRecord) {
        final model = DiscoverDetailViewModel.of(
          (answer.value as MediaSeerrRecord).details,
        );
        final numbers = [
          for (final season in model.seasons)
            if (season.seasonNumber > 0 && season.episodeCount > 0)
              season.seasonNumber,
        ];
        return numbers.isEmpty
            ? null
            : (seerr: connection.id, tvId: tvId, numbers: numbers);
      }
    }
    return null;
  }

  /// Opens the episodes graph; its best episode opens that episode's sheet.
  void _openGraph({
    required String seerr,
    required int tvId,
    required List<int> numbers,
    required List<MediaSeason> seasons,
    required List<MediaRow> rows,
    required String title,
    required TitleLight? light,
    required bool operator,
  }) {
    AppBottomSheet.showScrollable<void>(
      context: context,
      title: 'Episodes graph',
      subtitle: [if (title.isNotEmpty) title, 'TMDB votes'].join(dotSeparator),
      showClose: true,
      initialSize: 0.92,
      minSize: 0.5,
      builder: (sheet, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          MediaEpisodesGraphSheet(
            connectionId: seerr,
            tvId: tvId,
            seasonNumbers: numbers,
            seasons: seasons,
            light: light,
            onOpenEpisode: (season, number) {
              final episode = [
                for (final s in seasons)
                  for (final e in s.episodes)
                    if (e.season == season && e.number == number) e,
              ].firstOrNull;
              if (episode == null) return;
              Navigator.of(sheet).pop();
              _openEpisode(
                episode,
                seasons: seasons,
                rows: rows,
                title: title,
                light: light,
                operator: operator,
              );
            },
          ),
        ],
      ),
    );
  }

  /// Opens [episode]'s sheet, bound to the Sonarr, the Seerr and the media
  /// server the page reads.
  void _openEpisode(
    MediaEpisode episode, {
    required List<MediaSeason> seasons,
    required List<MediaRow> rows,
    required String title,
    required TitleLight? light,
    required bool operator,
  }) {
    final settings = ref.read(currentSettingsProvider);
    String name(ServiceInstance c) => settings.connectionTitle(c.id, c.service);
    MediaEpisodeSonarr? sonarr;
    String? seerr;
    MediaEpisodeServer? server;
    for (final row in rows) {
      if (row case MediaConnectionRow(
        :final connection,
        reading: MediaReadingAnswered(:final answer),
      )) {
        switch (answer.value) {
          case MediaSonarrCopy(:final series?)
              when sonarr == null || connection.id == focus:
            sonarr = (
              connection: connection,
              name: name(connection),
              seriesId: series.id,
              profileId: series.qualityProfileId,
            );
          case MediaSeerrRecord():
            seerr ??= connection.id;
          case MediaStreamCopy(episodes: _?)
              when server == null || connection.id == focus:
            server = (connection: connection, name: name(connection));
        }
      }
    }
    // Bazarr follows one Sonarr: its languages, when it is the one shown.
    final bazarr = _bazarrEpisodesOf(rows);
    final subtitles = bazarr == null || bazarr.arr != sonarr?.connection.id
        ? null
        : {for (final e in bazarr.episodes) e.sonarrEpisodeId: e};
    final tvId = mediaKey.tmdbId;
    AppBottomSheet.showScrollable<void>(
      context: context,
      initialSize: 0.92,
      minSize: 0.5,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          MediaEpisodeSheet(
            seriesTitle: title,
            seasons: seasons,
            season: episode.season,
            number: episode.number,
            operator: operator,
            sonarr: sonarr,
            seerr: seerr == null || tvId == null
                ? null
                : (connectionId: seerr, tvId: tvId),
            server: server,
            subtitles: subtitles,
            light: light,
            onPlay: (item) {
              final on = server;
              if (on != null) _playOn(on.connection, item.id, item.title);
            },
            onChanged: () {
              if (!mounted) return;
              for (final row in ref.read(mediaRowsProvider(mediaKey))) {
                if (row.service == ServiceKey.sonarr) {
                  retryMediaRow(ref, mediaKey, row);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// Asks the Sonarr that tracks the series for [season]'s missing episodes.
  Future<void> _searchMissing(MediaSeason season, List<MediaRow> rows) async {
    final sonarr = [
      for (final row in rows)
        if (row
            case MediaConnectionRow(
              :final connection,
              reading: MediaReadingAnswered(:final answer),
            )
            when answer.value is MediaSonarrCopy &&
                (answer.value as MediaSonarrCopy).series != null)
          connection,
    ];
    final connection =
        sonarr.where((c) => c.id == focus).firstOrNull ?? sonarr.firstOrNull;
    if (connection == null) return;
    final name = ref
        .read(currentSettingsProvider)
        .connectionTitle(connection.id, connection.service);
    final missing = season.missing;
    try {
      await ref.read(sonarrServiceForProvider(connection.id)).searchEpisodes([
        for (final e in missing) ?e.sonarrId,
      ]);
      if (!mounted) return;
      SnackBarHelper.success(
        context,
        missing.length == 1
            ? '$name is searching for it'
            : '$name is searching for the ${missing.length}',
      );
    } catch (error) {
      if (mounted) {
        SnackBarHelper.error(
          context,
          'Could not ask $name to search',
          detail: error,
        );
      }
    }
  }

  /// The requests waiting on the operator, one card each; only the first
  /// may lead.
  Widget _decisionCards(
    List<MediaPendingRequest> decisions, {
    required String title,
    required bool leads,
    required TitleLight? light,
    required List<MediaRow> rows,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, pending) in decisions.indexed) ...[
        if (index > 0) const SizedBox(height: AppSpacing.md),
        MediaDecisionCard(
          pending: pending,
          title: title,
          leads: leads && index == 0,
          light: light,
          // An answer changes Seerr's record, and an approval the arr's.
          onDecided: () {
            if (!mounted) return;
            for (final row in ref.read(mediaRowsProvider(mediaKey))) {
              if (row.service == ServiceKey.seerr ||
                  row.service == ServiceKey.radarr ||
                  row.service == ServiceKey.sonarr) {
                retryMediaRow(ref, mediaKey, row);
              }
            }
          },
        ),
      ],
    ],
  );

  /// `4 services`: the services the rows speak for, each once.
  String _servicesCount(List<MediaRow> rows) {
    final services = {
      for (final row in rows)
        if (row is MediaConnectionRow) row.service,
    };
    return services.length == 1 ? '1 service' : '${services.length} services';
  }

  /// The operator's sections, closed: each says what it holds in one line
  /// ([mediaManageSummaries]).
  List<Widget> _manage(List<MediaRow> rows, SettingsModel settings) {
    final seerr = _seerrManage(rows, settings);
    List<Widget> onlySeerr() => seerr.isEmpty
        ? const []
        : [
            MediaHeading('Manage', key: _manageKey),
            MediaGroup(children: seerr),
          ];
    if (!mediaKey.isMovie) {
      final held = [
        for (final row in rows)
          if (row case MediaConnectionRow(
            :final connection,
            reading: MediaReadingAnswered(:final answer),
          ))
            if (answer.value case MediaSonarrCopy(
              :final series?,
              :final episodes,
            ))
              (
                connection: connection,
                name: settings.connectionTitle(
                  connection.id,
                  connection.service,
                ),
                series: series,
                episodes: episodes,
              ),
      ];
      if (held.isEmpty) return onlySeerr();
      return [
        MediaHeading('Manage', key: _manageKey),
        MediaSeriesManage(
          copies: held,
          title: MediaIdentity.of(rows)?.title ?? '',
          mediaKey: mediaKey,
          subtitles: _bazarrEpisodesOf(rows),
          onChanged: () => _readArrsAgain(rows),
          more: seerr,
        ),
      ];
    }
    final summaries = mediaManageSummaries(
      rows,
      title: (connection) =>
          settings.connectionTitle(connection.id, connection.service),
    );
    if (summaries == null) return onlySeerr();
    final searches = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (
              name: settings.connectionTitle(connection.id, connection.service),
              target: ReleaseSearchTarget.movie(
                movieId: movie.id,
                label: truncateTitle(movie.title),
              ).stampedWith(connection.id),
            ),
    ];
    final held = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (
              name: settings.connectionTitle(connection.id, connection.service),
              target: (connection: connection, movie: movie),
            ),
    ];
    final title = MediaIdentity.of(rows)?.title ?? '';
    void remove(_RadarrHeld copy) => _remove(
      copy,
      title: title,
      keeping: [
        for (final other in held)
          if (other.target != copy && other.target.movie.hasFile) other.name,
      ],
    );
    return [
      MediaHeading('Manage', key: _manageKey),
      MediaGroup(
        children: [
          MediaManageRow(
            title: 'Files & quality',
            summary: summaries.files,
            body: (context) => _Files(
              rows: rows,
              settings: settings,
              onChanged: () => _readArrsAgain(rows),
            ),
          ),
          MediaManageRow(
            title: 'History',
            summary: summaries.history,
            body: (context) => _History(rows: rows, settings: settings),
          ),
          if (summaries.subtitles case final subtitles?)
            MediaManageRow(
              title: 'Subtitles',
              summary: subtitles,
              body: (context) => _Subtitles(rows: rows, settings: settings),
            ),
          MediaManageRow(
            title: 'Search releases',
            summary: summaries.search,
            // One copy: the row is the way in. More: it opens on the copies,
            // and the search goes to the one chosen.
            onTap: searches.length == 1
                ? () => showReleaseSearch(context, ref, searches.single.target)
                : null,
            body: searches.length > 1
                ? (context) => MediaCopyChoices<ReleaseSearchTarget>(
                    verb: 'Search releases on',
                    copies: searches,
                    onChoose: (target) =>
                        showReleaseSearch(context, ref, target),
                  )
                : null,
          ),
          if (held case [final copy])
            MediaManageRow(
              title: 'Remove from ${copy.name}',
              summary: copy.target.movie.monitored
                  ? 'Stops ${copy.name} looking for it'
                  : 'Stops ${copy.name} tracking it',
              onTap: () => remove(copy.target),
            )
          else if (held.isNotEmpty)
            MediaManageRow(
              title: 'Remove a copy',
              summary: _names([for (final copy in held) copy.name]),
              body: (context) => MediaCopyChoices<_RadarrHeld>(
                verb: 'Remove from',
                copies: held,
                onChoose: remove,
              ),
            ),
          ...seerr,
        ],
      ),
    ];
  }

  /// Manage's rows that go through Seerr, after the arrs' own: removing a
  /// copy from a server only Seerr reaches, then clearing the title from each
  /// Seerr that has a record of it. Each Seerr's account decides: a row it
  /// may not act on says why, and does nothing.
  List<Widget> _seerrManage(List<MediaRow> rows, SettingsModel settings) {
    final title = MediaIdentity.of(rows)?.title ?? '';
    String nameOf(ServiceInstance connection) =>
        settings.connectionTitle(connection.id, connection.service);
    String? cannot(ServiceInstance seerr) => switch (ref
        .watch(roleGateProvider(seerr.id))
        .operatorAction(SeerrAbility.manageMedia)) {
      Live() => null,
      Dimmed(:final reason) => reason,
      Absent() => '',
    };
    Widget act({
      required String label,
      required String summary,
      required String? reason,
      required VoidCallback onTap,
    }) => MediaManageRow(
      title: label,
      summary: reason ?? summary,
      onTap: reason == null ? onTap : null,
    );
    return [
      for (final row in rows)
        if (row case MediaThroughSeerrRow(
          :final seerr,
          :final copy,
          :final mediaInfo,
        ))
          if ((intOrNull(mediaInfo?['id']), cannot(seerr)) case (
            final mediaId?,
            final reason,
          ) when reason != '')
            act(
              label: 'Remove from ${copy.serverName(connectionTitle: nameOf)}',
              summary: 'Through ${nameOf(seerr)}, with its files',
              reason: reason,
              onTap: () => _removeThroughSeerr(
                seerr,
                mediaId,
                is4k: copy.copy.is4k,
                server: copy.serverName(connectionTitle: nameOf),
                title: title,
              ),
            ),
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaSeerrRecord(:final mediaInfo?))
            if ((intOrNull(mediaInfo['id']), cannot(connection)) case (
              final mediaId?,
              final reason,
            ) when reason != '')
              act(
                label: 'Clear from ${nameOf(connection)}',
                summary: 'Forgets its requests and status',
                reason: reason,
                onTap: () => _clearFromSeerr(
                  connection,
                  mediaId,
                  mediaInfo: mediaInfo,
                  title: title,
                ),
              ),
    ];
  }

  /// Clears the title from [seerr] (Seerr's "Clear data") after asking, then
  /// reads every Seerr again.
  Future<void> _clearFromSeerr(
    ServiceInstance seerr,
    int mediaId, {
    required Map<String, dynamic> mediaInfo,
    required String title,
  }) async {
    final name = ref
        .read(currentSettingsProvider)
        .connectionTitle(seerr.id, seerr.service);
    final requests = mediaInfo['requests'];
    // 4 and 5, partly and fully there, read the same in every numbering.
    bool there(Object? code) => code == 4 || code == 5;
    final clearing = seerrClearing(
      title: title,
      name: name,
      requests: requests is List ? requests.length : 0,
      onServer: there(mediaInfo['status']) || there(mediaInfo['status4k']),
    );
    await _seerrAct(
      clearing,
      failure: 'Could not clear $title from $name',
      done: 'Cleared from $name',
      act: () =>
          ref.read(seerrServiceForProvider(seerr.id)).deleteMedia(mediaId),
      readAgain: const {ServiceKey.seerr},
    );
  }

  /// Removes the title's copy from [server] through [seerr], which deletes
  /// its files with it, after asking; then reads Seerr and the arrs again.
  Future<void> _removeThroughSeerr(
    ServiceInstance seerr,
    int mediaId, {
    required bool is4k,
    required String server,
    required String title,
  }) async {
    final removal = seerrArrRemoval(
      title: title,
      server: server,
      seerr: ref
          .read(currentSettingsProvider)
          .connectionTitle(seerr.id, seerr.service),
    );
    await _seerrAct(
      removal,
      failure: 'Could not remove $title from $server',
      done: 'Removed from $server',
      act: () => ref
          .read(seerrServiceForProvider(seerr.id))
          .deleteMediaFile(mediaId, is4k: is4k),
      readAgain: const {ServiceKey.seerr, ServiceKey.radarr, ServiceKey.sonarr},
    );
  }

  /// Asks [words]' question; on a yes does [act], says [done] or [failure],
  /// and reads the rows of [readAgain] again.
  Future<void> _seerrAct(
    SeerrRemoval words, {
    required String failure,
    required String done,
    required Future<void> Function() act,
    required Set<ServiceKey> readAgain,
  }) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: words.title,
      message: words.message,
      icon: Icons.delete_outline_rounded,
      cancelLabel: 'Keep it',
      confirmLabel: words.confirm,
    );
    if (!result.confirmed || !mounted) return;
    try {
      await act();
      if (!mounted) return;
      SnackBarHelper.success(context, done);
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(context, failure, detail: error);
    }
    for (final row in ref.read(mediaRowsProvider(mediaKey))) {
      if (readAgain.contains(row.service)) retryMediaRow(ref, mediaKey, row);
    }
  }

  /// `Radarr`, `Radarr and Radarr 4K`, `A, B and C`.
  static String _names(List<String> names) => switch (names) {
    [] => '',
    [final one] => one,
    _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
  };

  /// Removes [copy] from its Radarr, after the question removing asks: what
  /// it takes, whether its files go, whether Radarr may add it again. Then
  /// every Radarr is read again.
  Future<void> _remove(
    _RadarrHeld copy, {
    required String title,
    required List<String> keeping,
  }) async {
    final name = ref
        .read(currentSettingsProvider)
        .connectionTitle(copy.connection.id, copy.connection.service);
    final removal = mediaRemoval(
      title: title,
      name: name,
      sizeOnDisk: copy.movie.sizeOnDisk,
      monitored: copy.movie.monitored,
      keeping: keeping,
    );
    final result = await showAppConfirmDialog(
      context: context,
      title: removal.title,
      message: removal.message,
      note: mediaWatchedByNote(ref, mediaKey),
      icon: Icons.delete_outline_rounded,
      cancelLabel: 'Keep it',
      confirmLabel: removal.confirm(deleteFiles: false, exclude: false),
      confirmLabelFor: (checked) => removal.confirm(
        deleteFiles: checked('files'),
        exclude: checked('exclude'),
      ),
      options: [
        if (removal.filesLabel case final label?)
          AppConfirmOption(
            key: 'files',
            label: label,
            subtitle: 'Its folder on your server. This cannot be undone.',
          ),
        AppConfirmOption(
          key: 'exclude',
          label: "Don't add it again",
          subtitle: "Keeps $name's import lists from bringing it back",
        ),
      ],
    );
    if (!result.confirmed || !mounted) return;
    try {
      await ref
          .read(radarrServiceForProvider(copy.connection.id))
          .deleteMovie(
            copy.movie.id,
            deleteFiles: result.option('files'),
            addImportExclusion: result.option('exclude'),
          );
      if (!mounted) return;
      SnackBarHelper.success(context, 'Removed from $name');
      for (final row in ref.read(mediaRowsProvider(mediaKey))) {
        if (row.service == ServiceKey.radarr) {
          retryMediaRow(ref, mediaKey, row);
        }
      }
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not remove $title from $name',
        detail: error,
      );
    }
  }
}

/// A film one Radarr holds: the connection, and its record there.
typedef _RadarrHeld = ({ServiceInstance connection, RadarrMovie movie});

/// Artwork, poster and title: the backdrop in a slab, the poster rising out
/// of its foot, the title beside the poster, then the meta line.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.identity,
    required this.kind,
    required this.waiting,
    required this.marks,
    required this.onArtDrawn,
    required this.backdropHeight,
    this.heroTag,
    this.posterUrl,
    this.light,
  });

  /// See [MediaPage.heroTag] and [MediaPage.posterUrl].
  final String? heroTag;
  final String? posterUrl;

  /// The slab's height: 214 on the phone, growing with the page's width.
  final double backdropHeight;

  /// Told when the backdrop or the poster has been drawn.
  final ValueChanged<String> onArtDrawn;

  final MediaIdentity? identity;
  final MediaKind kind;

  /// Nobody has said who the title is yet: the artwork shimmers rather than
  /// standing in.
  final bool waiting;

  final List<String> marks;

  /// The title's light, or null for the lamp.
  final TitleLight? light;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final identity = this.identity;
    // The poster grows with the slab, up to half again its phone size.
    final scale = (backdropHeight / 214).clamp(1.0, 1.5);
    final posterWidth = 88.0 * scale;
    final posterHeight = 132.0 * scale;
    final rise = 52.0 * scale;

    final stacked = mediaStacked(context);
    final backdrop = Container(
      height: backdropHeight,
      decoration: BoxDecoration(
        color: room.raised,
        borderRadius: BorderRadius.circular(AppRadius.slab),
        boxShadow: AppElevation.hero(scheme, light: light?.light),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch ((identity?.backdropUrl, identity?.posterUrl)) {
        _ when waiting => const ShimmerPlaceholder(height: double.infinity),
        (final String backdrop, _) when backdrop.isNotEmpty => _Artwork(
          url: backdrop,
          onDrawn: onArtDrawn,
          fallback: _Plate(kind: kind, well: true),
        ),
        // No backdrop: the poster, veiled, so the slab is still the title's.
        // Decoded once, at the poster's box.
        (_, final String poster) when poster.isNotEmpty => _Artwork.veiled(
          url: poster,
          headers: identity?.artHeaders,
          decodeBox: Size(posterWidth, posterHeight),
          onDrawn: onArtDrawn,
          fallback: _Plate(kind: kind, well: true),
        ),
        _ => _Plate(kind: kind, well: true),
      },
    );
    // The tile's poster stands in until the title's own is known.
    final ownPoster = (identity?.posterUrl ?? '').isNotEmpty;
    final posterArt = ownPoster ? identity!.posterUrl : posterUrl;
    Widget poster = Container(
      width: posterWidth,
      height: posterHeight,
      decoration: BoxDecoration(
        color: room.raised,
        borderRadius: BorderRadius.circular(AppRadius.poster),
        // Artwork is not palette: the plate's line in both rooms.
        border: Border.all(color: AppColors.plateOutline),
        boxShadow: AppElevation.poster(scheme, light: light?.light),
      ),
      clipBehavior: Clip.antiAlias,
      child: waiting && (posterArt ?? '').isEmpty
          ? const ShimmerPlaceholder(height: double.infinity)
          : _Artwork(
              url: posterArt,
              headers: ownPoster ? identity!.artHeaders : null,
              decodeBox: Size(posterWidth, posterHeight),
              onDrawn: onArtDrawn,
              fallback: _Plate(kind: kind),
            ),
    );
    if (heroTag case final tag?) {
      poster = Hero(
        tag: tag,
        transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
        child: poster,
      );
    }
    final title = Semantics(
      header: true,
      child: Text(
        identity?.title ?? '',
        maxLines: stacked ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.media.copyWith(color: room.ink),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The poster rises [rise] into the artwork, and the title beside it
        // sizes the hero: a title on two lines pushes the meta line down
        // rather than running over it.
        Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: backdropHeight,
              child: backdrop,
            ),
            Padding(
              padding: EdgeInsets.only(top: backdropHeight - rise),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  poster,
                  if (!stacked) ...[
                    const SizedBox(width: AppSpacing.slabY),
                    Expanded(
                      child: Padding(
                        // Clear of the artwork: the title starts under it.
                        padding: EdgeInsets.only(top: rise + AppSpacing.md),
                        child: title,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // At a large reading size the title takes the whole width.
        if (stacked) ...[const SizedBox(height: AppSpacing.md), title],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              identity?.metaLine ?? '',
              style: AppType.label
                  .weight(FontWeight.w400)
                  .copyWith(color: room.inkSecondary),
            ),
            for (final mark in marks) _Mark(mark),
          ],
        ),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: room.inkTertiary),
      ),
      child: Text(
        text,
        style: AppType.micro.copyWith(color: room.inkSecondary),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.url,
    required this.fallback,
    this.headers,
    this.decodeBox,
    this.onDrawn,
  }) : veiled = false,
       opacity = 1;

  /// [url] blurred and dimmed over the plate's well: a poster standing in
  /// for a backdrop.
  const _Artwork.veiled({
    required this.url,
    required this.fallback,
    this.headers,
    this.decodeBox,
    this.onDrawn,
    this.opacity = 0.72,
  }) : veiled = true;

  final String? url;

  /// Sent with the request: a media server's credential for its own poster.
  final Map<String, String>? headers;

  /// What stands in when there is no picture, or it cannot be fetched.
  final Widget fallback;

  /// The box the picture is decoded for, when it is not the one it fills.
  final Size? decodeBox;

  final bool veiled;

  /// How much of the veiled picture shows over the well: less under words.
  final double opacity;

  /// Told once the picture is drawn, with its address.
  final ValueChanged<String>? onDrawn;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return fallback;
    final picture = ArtworkDecodeBox(
      box: decodeBox,
      builder: (context, decode) => CachedNetworkImage(
        imageUrl: url,
        httpHeaders: headers,
        cacheManager: pinnedImageCacheFor(url),
        memCacheWidth: decode.width,
        memCacheHeight: decode.height,
        fit: BoxFit.cover,
        imageBuilder: (context, image) {
          onDrawn?.call(url);
          return Image(image: image, fit: BoxFit.cover);
        },
        placeholder: (context, url) =>
            const ShimmerPlaceholder(height: double.infinity),
        errorWidget: (context, url, error) => fallback,
      ),
    );
    if (!veiled) return picture;
    return ColoredBox(
      color: AppColors.plateWell,
      child: Opacity(
        opacity: opacity,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: 24,
            sigmaY: 24,
            tileMode: TileMode.clamp,
          ),
          child: SizedBox.expand(child: picture),
        ),
      ),
    );
  }
}

/// The side track's width when the page takes two: the servers and Manage,
/// drawn for the phone's column and a little more.
const double _sideTrack = 380;

/// The collection the title belongs to, in one slab over its own artwork,
/// veiled: its name, and how much of it the household holds. Taps
/// into the collection.
class _CollectionBand extends StatelessWidget {
  const _CollectionBand({required this.collection, required this.held});

  final CollectionInfo collection;

  /// Null until Seerr has counted it, and when it could not: then the band
  /// names what it is and states no figure.
  final MediaCollectionHeld? held;

  @override
  Widget build(BuildContext context) {
    final count = held;
    final words = count == null
        ? 'Collection'
        : '${count.held} of ${count.total} on your server';
    final art = collection.backdropPath ?? collection.posterPath;
    return PressableScale(
      onTap: () => context.openCollection(
        collection.id,
        heroTag: 'collection_${collection.id}',
      ),
      semanticLabel: '${collection.name}, $words',
      excludeChildSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.slab),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.slab),
            border: Border.all(color: AppColors.plateOutline),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: _Artwork.veiled(
                  url: ImageUtils.buildTmdbPosterUrl(art, size: 'w300'),
                  fallback: const ColoredBox(color: AppColors.plateSurface),
                  // Blurred: a small decode carries it.
                  decodeBox: const Size(120, 68),
                  opacity: 0.56,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collection.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.feature.copyWith(
                              color: AppColors.plateInk,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            words,
                            style: AppType.label
                                .weight(FontWeight.w600)
                                .copyWith(color: AppColors.plateInk),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 24,
                      color: AppColors.plateInk,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Missing artwork's stand-in: the plate, dark in both rooms (brand book,
/// *Plates*), with the kind of title it stands for.
class _Plate extends StatelessWidget {
  const _Plate({required this.kind, this.well = false});

  final MediaKind kind;

  /// The backdrop's letterboxed well rather than a poster's plate.
  final bool well;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ColoredBox(
        color: well ? AppColors.plateWell : AppColors.plateSurface,
        child: Center(
          child: Icon(
            kind == MediaKind.movie ? Icons.movie_outlined : Icons.tv_outlined,
            size: well ? 40 : 28,
            color: AppColors.plateDimInk,
          ),
        ),
      ),
    );
  }
}

/// The four scores in one slab, each with its source; a source with no
/// figure reads `—`.
class _Scores extends StatelessWidget {
  const _Scores({
    required this.scores,
    required this.showMetacritic,
    this.series = false,
  });

  final MediaScores scores;

  /// The requester never sees Metacritic: Seerr has none.
  final bool showMetacritic;

  /// A series has two: TMDB's, and Rotten Tomatoes' through Seerr. IMDb and
  /// Metacritic reach the app for movies alone.
  final bool series;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    String figure(num? value, {bool decimal = true}) => value == null
        ? '—'
        : decimal
        ? value.toStringAsFixed(1)
        : '$value';
    Widget line(List<(String, String)> cells) => _ScoresLine(cells);
    final cells = [
      ('TMDB', figure(scores.tmdb)),
      if (!series) ('IMDb', figure(scores.imdb)),
      ('Rotten Tomatoes', figure(scores.rottenTomatoes, decimal: false)),
      if (showMetacritic && !series)
        ('Metacritic', figure(scores.metacritic, decimal: false)),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: room.door,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: mediaStacked(context) && cells.length > 2
          // At a large reading size, two to a line.
          ? Column(
              children: [
                line(cells.take(2).toList()),
                Divider(height: 1, color: room.hair),
                line(cells.skip(2).toList()),
              ],
            )
          : line(cells),
    );
  }
}

class _ScoresLine extends StatelessWidget {
  const _ScoresLine(this.cells);

  final List<(String, String)> cells;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return IntrinsicHeight(
      child: Row(
        children: [
          for (final (index, cell) in cells.indexed) ...[
            if (index > 0) VerticalDivider(width: 1, color: room.hair),
            Expanded(
              child: Semantics(
                label: '${cell.$1}: ${cell.$2 == '—' ? 'no score' : cell.$2}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.row),
                  // The figures share a line, so they compare at a glance;
                  // a label that needs two lines (`Rotten Tomatoes`) grows
                  // down, under its own figure.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cell.$2,
                        style: AppType.figure.copyWith(color: room.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        cell.$1,
                        style: AppType.micro
                            .weight(FontWeight.w400)
                            .copyWith(color: room.inkTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The queue's downloads of the title: those the arrs hold it under, on one
/// of the page's connections (a Radarr movie or a Sonarr series of [rows]),
/// in the queue's own order.
List<ServiceQueueItem> _titleDownloads(
  List<MediaRow> rows,
  List<ServiceQueueItem> queue,
) {
  final held = <(ServiceKey, String, int)>{};
  for (final row in rows) {
    if (row case MediaConnectionRow(
      :final connection,
      reading: MediaReadingAnswered(:final answer),
    )) {
      switch (answer.value) {
        case MediaRadarrCopy(movie: final movie?):
          held.add((ServiceKey.radarr, connection.id, movie.id));
        case MediaSonarrCopy(series: final series?):
          held.add((ServiceKey.sonarr, connection.id, series.id));
        default:
      }
    }
  }
  return [
    for (final item in queue)
      // A finished download the arr will not import is no download any more,
      // as on the Home: the copy's row says so, with Review the imports.
      if (item.fault != InFlightFault.needsImport)
        if (item.mediaId case final id?
            when held.contains((item.service, item.instanceId, id)))
          item,
  ];
}

/// The title's downloads under its lead: each one a Home download row, three
/// at most, then how many more are in Activity. A row opens the download's own
/// page beside or over the title, never by switching to Activity.
class _TitleDownloads extends StatelessWidget {
  const _TitleDownloads({required this.items});

  final List<ServiceQueueItem> items;

  /// Rows drawn before the rest is counted.
  static const _limit = 3;

  @override
  Widget build(BuildContext context) {
    final more = items.length - _limit;
    return MediaGroup(
      children: [
        for (final item in items.take(_limit))
          DownloadRow(
            key: ValueKey('${item.service}-${item.instanceId}-${item.id}'),
            item: item,
            onOpen: () => context.openDownload(item),
          ),
        if (more > 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => context.go(ServiceRoutes.activity),
              child: Text('$more more in Activity'),
            ),
          ),
      ],
    );
  }
}

/// The one action that leads, and the three beside it: Trailer, Watchlist,
/// Manage.
class _LeadBar extends StatelessWidget {
  const _LeadBar({
    required this.lead,
    required this.onPlay,
    required this.onTrailer,
    required this.onManage,
    this.watchlist,
    this.request,
    this.onRequest,
    this.onWatch,
    required this.onWatchAt,
    this.onAdd,
    this.light,
    this.primary,
    required this.hasTrailer,
    required this.showManage,
    required this.serverName,
  });

  final MediaLead lead;

  /// The title's light: the lead takes its tinted fill. Null, the ink.
  final TitleLight? light;
  final void Function(MediaLeadPlay lead) onPlay;
  final VoidCallback? onTrailer;
  final VoidCallback onManage;

  /// Whether the title is on the watchlist, and the toggle; null without a
  /// Seerr that has answered.
  final ({bool on, VoidCallback onTap})? watchlist;

  /// What Request says and may do, when it leads.
  final _Request? request;

  /// Opens the request sheet, when a request can be made.
  final VoidCallback? onRequest;

  /// Opens Seerr's link to the title, when Seerr has it on the server.
  final VoidCallback? onWatch;

  /// Opens Seerr's link for a Watch that leads.
  final void Function(Uri url) onWatchAt;

  /// Opens the add sheet, for an Add that leads.
  final void Function(MediaLeadAdd lead)? onAdd;

  /// What stands in the lead's place when something else answers first:
  /// a request that waits on the operator. The buttons under it stay.
  final Widget? primary;
  final bool hasTrailer;
  final bool showManage;
  final String Function(MediaLeadPlay lead) serverName;

  @override
  Widget build(BuildContext context) {
    final label = switch (lead) {
      // A series plays the episode: `Resume S2 E3`, `Play S2 E4`.
      MediaLeadPlay(:final resume, episode: final episode?) =>
        '${resume ? 'Resume' : 'Play'} '
            '${formatArrEpisodeCode(episode.seasonNumber, episode.episodeNumber)}',
      MediaLeadPlay(:final resume) =>
        '${resume ? 'Resume' : 'Play'} on ${serverName(lead as MediaLeadPlay)}',
      MediaLeadAdd(:final arr) => 'Add to ${arr.title}',
      MediaLeadWatch(:final server) => 'Watch on ${server.title}',
      MediaLeadRequest() =>
        request?.watch?.label ?? request?.words.label ?? 'Request',
      MediaLeadCopy(:final status, :final connection) => resolveMediaAction(
        status,
        const MediaActionCapabilities(
          canSearch: true,
          canInteractiveSearch: true,
          canOpenQueue: true,
        ),
        serviceName: connection.service.title,
      ).label,
      MediaLeadTrailer() || MediaLeadNone() || MediaLeadWaiting() => null,
    };
    // Under an episode's Play, which one and how far: `The Second Cycle · 5
    // min left`, `Episode 4 · on Jellyfin`.
    final subtitle = switch (lead) {
      MediaLeadPlay(:final resume, episode: final episode?) => [
        if (episode.title.isNotEmpty) episode.title,
        if (resume)
          ?mediaTimeLeft(episode)
        else
          'on ${serverName(lead as MediaLeadPlay)}',
      ].join(dotSeparator),
      _ => null,
    };
    final trailerLeads = primary == null && lead is MediaLeadTrailer;
    final leadStyle = mediaLeadStyle(context, light);
    final watchlist = this.watchlist;
    final secondaries = <(String, IconData, VoidCallback?, String?)>[
      if (hasTrailer && !trailerLeads)
        ('Trailer', Icons.smart_display_outlined, onTrailer, null),
      // The watchlist of the user the Seerr connection acts as
      // (F-seerr-actas): the glyph fills while the title is on it.
      if (watchlist != null)
        (
          'Watchlist',
          watchlist.on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          watchlist.onTap,
          // Heard as a state, since the glyph alone shows it.
          watchlist.on ? 'On your watchlist' : null,
        ),
      if (showManage) ('Manage', Icons.tune_rounded, onManage, null),
    ];
    final onLead = switch (lead) {
      final MediaLeadPlay play => () => onPlay(play),
      final MediaLeadAdd add when onAdd != null => () => onAdd!(add),
      final MediaLeadWatch watch => () => onWatchAt(watch.url),
      MediaLeadRequest() when request?.watch != null => onWatch,
      MediaLeadRequest() when request?.words.open ?? false => onRequest,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (primary case final primary?)
          primary
        else if (lead is MediaLeadWaiting)
          const ShimmerPlaceholder(height: DesignTokens.sizeButtonL)
        else if (label != null && label.isNotEmpty)
          // An account that may not ask for this kind keeps Request, dimmed
          // and tappable, and is told why.
          if (lead is MediaLeadRequest &&
              (request?.words.open ?? false) &&
              onRequest != null)
            RoleGatedAction.builder(
              verdict: request!.verdict,
              onTap: onRequest!,
              builder: (context, onPressed, annotate) => FilledButton(
                onPressed: onPressed,
                style: leadStyle,
                child: Row(
                  children: [
                    Expanded(child: annotate(Text(label))),
                    const Icon(Icons.add_rounded, size: 20),
                  ],
                ),
              ),
            )
          else
            FilledButton(
              onPressed: onLead,
              style: leadStyle,
              child: Row(
                children: [
                  Expanded(
                    child: subtitle == null || subtitle.isEmpty
                        ? Text(label)
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.meta.weight(FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                  ),
                  Icon(switch (lead) {
                    MediaLeadPlay() => Icons.play_arrow_rounded,
                    MediaLeadAdd() => Icons.add_rounded,
                    MediaLeadWatch() => Icons.open_in_new_rounded,
                    MediaLeadRequest() when request?.watch != null =>
                      Icons.open_in_new_rounded,
                    MediaLeadRequest() when !(request?.words.open ?? true) =>
                      request!.words.icon,
                    MediaLeadRequest() => Icons.add_rounded,
                    _ => Icons.arrow_forward_rounded,
                  }, size: 20),
                ],
              ),
            )
        else if (trailerLeads)
          FilledButton.icon(
            onPressed: onTrailer,
            style: leadStyle,
            icon: const Icon(Icons.smart_display_outlined, size: 20),
            label: const Text('Trailer'),
          ),
        const SizedBox(height: AppSpacing.row),
        _SecondaryActions(secondaries),
      ],
    );
  }
}

/// The quiet actions under the lead, side by side, each the same width.
///
/// They keep their glyphs while every label fits beside one; a phone too
/// narrow for `Watchlist` and its glyph drops the glyphs before it cuts a
/// word, and one too narrow even for the words (or a large reading size)
/// puts them one to a line.
class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions(this.actions);

  final List<(String, IconData, VoidCallback?, String?)> actions;

  static const double _glyph = 17;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    Widget button(
      (String, IconData, VoidCallback?, String?) action, {
      required bool glyph,
      bool clip = false,
    }) {
      final (text, icon, onPressed, spoken) = action;
      final label = Text(
        text,
        semanticsLabel: spoken,
        maxLines: clip ? 1 : null,
        overflow: clip ? TextOverflow.ellipsis : null,
      );
      return glyph
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: _glyph),
              label: label,
            )
          : OutlinedButton(onPressed: onPressed, child: label);
    }

    Widget column() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, action) in actions.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          button(action, glyph: true),
        ],
      ],
    );

    if (mediaStacked(context)) return column();
    return LayoutBuilder(
      builder: (context, box) {
        final gaps = AppSpacing.row * (actions.length - 1);
        final each = (box.maxWidth - gaps) / actions.length;
        final style = OutlinedButtonTheme.of(context).style;
        final textStyle =
            style?.textStyle?.resolve(const {}) ??
            DefaultTextStyle.of(context).style;
        final padding =
            style?.padding?.resolve(const {})?.horizontal ?? 2 * AppSpacing.lg;
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double widthOf(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: textStyle),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final widest = actions
            .map((action) => widthOf(action.$1))
            .reduce((a, b) => a > b ? a : b);
        // The glyph, and the gap Material keeps between it and the label.
        const glyphRoom = _glyph + AppSpacing.sm;
        final glyph = widest + glyphRoom + padding <= each;
        if (!glyph && widest + padding > each) return column();
        return Row(
          children: [
            for (final (index, action) in actions.indexed) ...[
              if (index > 0) const SizedBox(width: AppSpacing.row),
              Expanded(child: button(action, glyph: glyph, clip: true)),
            ],
          ],
        );
      },
    );
  }
}

/// One row of "On your server", in the shape its case takes
/// ([MediaRowShape]): the connection on the left, a fixed 92; what it holds;
/// on the right the state, or the row's one way forward. A row with a way
/// forward is tapped whole, and speaks one sentence.
class _ServerRow extends StatelessWidget {
  const _ServerRow(this.view, {this.onTap});

  final MediaRowView view;

  /// The row's one way forward ([MediaRowView.way]).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final stacked = mediaStacked(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
      child: view.shape == MediaRowShape.notSetUp
          ? _notSetUp(room, stacked: stacked)
          : _reading(context, room, stacked: stacked),
    );
    final onTap = this.onTap;
    // A fault reads as one sentence, and its remedy is a button of its own:
    // the one amber fill.
    if (view.shape == MediaRowShape.fault) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: [view.name, view.state, view.detail].join('. '),
            excludeSemantics: true,
            child: content,
          ),
          if (view.action case final action?)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.row),
              child: FilledButton(
                onPressed: onTap,
                style: remedyFillStyle(context),
                child: Text(action),
              ),
            ),
        ],
      );
    }
    if (onTap == null) {
      return Semantics(
        container: true,
        label: view.spoken,
        excludeSemantics: true,
        child: content,
      );
    }
    return PressableScale(
      onTap: onTap,
      semanticLabel: view.spoken,
      excludeChildSemantics: true,
      child: content,
    );
  }

  /// Case a, dimmed and still the way in: the name, `Not
  /// set up` and what it would bring, and the pill that names the service.
  Widget _notSetUp(CupolaRoom room, {required bool stacked}) {
    final name = Text(
      view.name,
      style: AppType.row.copyWith(color: room.ink.withValues(alpha: 0.55)),
    );
    final state = Text(
      view.state,
      style: AppType.meta
          .weight(FontWeight.w600)
          .copyWith(color: room.inkSecondary.withValues(alpha: 0.72)),
    );
    final reason = Text(
      view.detail,
      style: AppType.caption
          .weight(FontWeight.w400)
          .copyWith(color: room.inkTertiary),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          name,
          state,
          if (view.detail.isNotEmpty) reason,
          if (view.action case final action?) ...[
            const SizedBox(height: AppSpacing.sm),
            _SetUpPill(action),
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(width: 92, child: name),
                  const SizedBox(width: AppSpacing.row),
                  Expanded(child: state),
                ],
              ),
              if (view.detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                reason,
              ],
            ],
          ),
        ),
        if (view.action case final action?) ...[
          const SizedBox(width: AppSpacing.row),
          _SetUpPill(action),
        ],
      ],
    );
  }

  Widget _reading(
    BuildContext context,
    CupolaRoom room, {
    required bool stacked,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(scheme, view.tone, surface: room.ground);
    final waiting = view.state.isEmpty;
    final secondary = AppType.meta
        .weight(FontWeight.w400)
        .copyWith(color: room.inkTertiary);
    final stateStyle = AppType.meta
        .weight(FontWeight.w600)
        .copyWith(color: room.inkSecondary);

    Widget state() => ConstrainedBox(
      // The state takes its own width, up to a third of the row: the detail
      // gets the rest, and a long state wraps inside its own column.
      constraints: const BoxConstraints(maxWidth: 150),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: view.hollow ? null : tone,
              border: view.hollow
                  ? Border.all(color: room.inkSecondary, width: 1.5)
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Flexible(child: Text(view.state, style: stateStyle)),
        ],
      ),
    );

    final middle = switch (view.shape) {
      _ when waiting => const Align(
        alignment: Alignment.centerLeft,
        child: ShimmerPlaceholder(width: 120, height: 12),
      ),
      MediaRowShape.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(view.state, style: stateStyle.copyWith(color: tone)),
          if (view.detail.isNotEmpty) Text(view.detail, style: secondary),
        ],
      ),
      MediaRowShape.fault => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                // On the first line's centre.
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  view.state,
                  style: stateStyle.copyWith(color: tone),
                ),
              ),
            ],
          ),
          if (view.detail.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(view.detail, style: secondary),
          ],
        ],
      ),
      _ => Text(view.detail, style: secondary),
    };

    final trailing = switch (view.shape) {
      _ when waiting => null,
      MediaRowShape.fault => null,
      MediaRowShape.failed => Text(
        view.action ?? '',
        style: AppType.label.copyWith(color: room.ink),
      ),
      _ => state(),
    };

    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(view.name, style: AppType.row.copyWith(color: room.ink)),
        if (view.via case final via?)
          Text(via, style: AppType.caption.copyWith(color: room.inkTertiary)),
      ],
    );
    // The quiet way to a server or a copy the household does not have yet.
    final add =
        (view.shape == MediaRowShape.claim ||
                view.way == MediaRowWay.addCopy) &&
            view.action != null
        ? Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 18, color: room.ink),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    view.action!,
                    style: AppType.label.copyWith(color: room.ink),
                  ),
                ),
              ],
            ),
          )
        : null;
    // At a large reading size each part takes the whole width, one under
    // the other: the name, what it holds, its state or its way forward.
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          name,
          if (waiting ||
              view.detail.isNotEmpty ||
              view.shape == MediaRowShape.failed) ...[
            const SizedBox(height: AppSpacing.xs),
            middle,
          ],
          if (trailing != null) ...[
            const SizedBox(height: AppSpacing.xs),
            trailing,
          ],
          ?add,
        ],
      );
    }
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            children: [
              SizedBox(width: 92, child: name),
              const SizedBox(width: AppSpacing.row),
              Expanded(child: middle),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.row),
                trailing,
              ],
            ],
          ),
        ),
        ?add,
      ],
    );
  }
}

/// `+ Set up Seerr`: the quiet pill a row that is not set up ends with. The
/// row around it is the target; the pill names where it leads.
class _SetUpPill extends StatelessWidget {
  const _SetUpPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final ink = room.inkSecondary.withValues(alpha: 0.8);
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.row),
      decoration: BoxDecoration(
        color: room.fillControl,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: room.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, size: 16, color: ink),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppType.meta.weight(FontWeight.w600).copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

/// Files & quality, open: every copy under its connection's name, its file
/// as the service records it, or the row a copy with nothing on disk keeps.
class _Files extends StatelessWidget {
  const _Files({
    required this.rows,
    required this.settings,
    required this.onChanged,
  });

  final List<MediaRow> rows;
  final SettingsModel settings;

  /// Told after a copy's profile or monitoring changed.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final copies = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (
              connection: connection,
              movie: movie,
              file: movie.movieFile,
              folder: movie.path,
            ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              [
                settings.connectionTitle(
                  copy.connection.id,
                  copy.connection.service,
                ),
                if (copy.file?.qualityName case final quality?
                    when quality.isNotEmpty)
                  qualityWords(quality),
                if (copy.file?.size case final size? when size > 0)
                  formatBytes(size),
              ].join(dotSeparator),
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
          switch (copy.file) {
            ArrMediaFile(:final fileName?) => FileInfoSection.file(
              fileName: fileName,
              releasedAs: copy.file!.releasedAs,
              path: copy.folder,
            ),
            _ => const FileInfoSection.missing(),
          },
          _CopyControls(
            connection: copy.connection,
            name: settings.connectionTitle(
              copy.connection.id,
              copy.connection.service,
            ),
            movie: copy.movie,
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }
}

/// What a copy's arr does about it, edited where it is read: its quality
/// profile and whether it is monitored, in the words the add sheet uses.
/// A change shows at once and is written to the arr; [onChanged] then reads
/// the copy again, and a write that failed puts the old value back.
class _CopyControls extends ConsumerStatefulWidget {
  const _CopyControls({
    required this.connection,
    required this.name,
    required this.movie,
    required this.onChanged,
  });

  final ServiceInstance connection;
  final String name;
  final RadarrMovie movie;
  final VoidCallback onChanged;

  @override
  ConsumerState<_CopyControls> createState() => _CopyControlsState();
}

class _CopyControlsState extends ConsumerState<_CopyControls> {
  /// What the user chose, until the copy read again says so.
  int? _profileId;
  bool? _monitored;

  @override
  void didUpdateWidget(_CopyControls old) {
    super.didUpdateWidget(old);
    if (old.movie != widget.movie) {
      _profileId = null;
      _monitored = null;
    }
  }

  Future<void> _write(
    Future<void> Function() write,
    VoidCallback undo,
    String failure,
  ) async {
    try {
      await write();
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(undo);
      SnackBarHelper.error(context, failure, detail: error);
    }
  }

  Future<void> _pickProfile(Map<int, String> profiles, int current) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: current,
      currentLabel: profiles[current] ?? '',
      options: [
        for (final MapEntry(:key, :value) in profiles.entries)
          MediaDetailValueOption(value: key, label: value),
      ],
    );
    if (picked == null || picked.value == current || !mounted) return;
    setState(() => _profileId = picked.value);
    await _write(
      () => ref
          .read(radarrServiceForProvider(widget.connection.id))
          .updateMovieProfile(widget.movie.id, picked.value),
      () => _profileId = null,
      'Could not change the profile in ${widget.name}',
    );
  }

  Future<void> _setMonitored(bool value) async {
    setState(() => _monitored = value);
    await _write(
      () => ref
          .read(radarrServiceForProvider(widget.connection.id))
          .updateMovieMonitored(widget.movie.id, value),
      () => _monitored = null,
      value
          ? 'Could not monitor it in ${widget.name}'
          : 'Could not stop monitoring it in ${widget.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final profiles =
        ref.watch(mediaRadarrProfilesProvider(widget.connection.id)).value ??
        const <int, String>{};
    final profileId = _profileId ?? widget.movie.qualityProfileId;
    final profile = profiles[profileId];
    final monitored = _monitored ?? widget.movie.monitored;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Unnamed until Radarr has said what its profiles are called.
        if (profile != null)
          MediaValueRow(
            label: 'Quality profile',
            value: Text(
              profile,
              textAlign: TextAlign.end,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
            onTap: profiles.length > 1 && profileId != null
                ? () => _pickProfile(profiles, profileId)
                : null,
          ),
        MediaSwitchRow(
          label: 'Monitor',
          detail: monitored
              ? 'Grabs it and upgrades it to ${profile ?? 'its profile'}'
              : '${widget.name} lists it and never looks for it',
          value: monitored,
          onChanged: _setMonitored,
        ),
        // A file the user already has, on this copy's server: the wizard is
        // bound to this connection, so it lands in this copy's library.
        MediaLinkRow(
          label: 'Import a file',
          detail: 'From a folder on the server',
          onTap: () async {
            await context.push(
              manualImportLocation(
                manualImportBrowsePath,
                ServiceKey.radarr,
                targetId: widget.movie.id,
                instanceId: widget.connection.id,
              ),
            );
            widget.onChanged();
          },
        ),
      ],
    );
  }
}

/// Subtitles, open: each Bazarr's languages for the movie, the ones on disk
/// and the ones it is still looking for.
class _Subtitles extends StatelessWidget {
  const _Subtitles({required this.rows, required this.settings});

  final List<MediaRow> rows;
  final SettingsModel settings;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final copies = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaBazarrCopy(:final movie?))
            (connection: connection, movie: movie),
    ];
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.s),
      child: Text(
        text,
        style: AppType.label.copyWith(color: room.inkSecondary),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final copy in copies) ...[
          if (copies.length > 1)
            label(
              settings.connectionTitle(
                copy.connection.id,
                copy.connection.service,
              ),
            ),
          if (copy.movie.presentLanguages.isNotEmpty) ...[
            label('On disk'),
            BazarrSubtitleLanguageWrap(languages: copy.movie.presentLanguages),
          ],
          if (copy.movie.missingLanguages.isNotEmpty) ...[
            label('Wanted'),
            BazarrSubtitleLanguageWrap(languages: copy.movie.missingLanguages),
          ],
        ],
      ],
    );
  }
}

/// History, open: each Radarr copy's own events, newest first, read when the
/// section opens.
class _History extends ConsumerWidget {
  const _History({required this.rows, required this.settings});

  final List<MediaRow> rows;
  final SettingsModel settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final copies = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (connection: connection, movieId: movie.id),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              settings.connectionTitle(
                copy.connection.id,
                copy.connection.service,
              ),
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
          switch (ref.watch(
            mediaRadarrHistoryProvider((
              connectionId: copy.connection.id,
              movieId: copy.movieId,
            )),
          )) {
            AsyncValue(:final value?) when value.isEmpty => Text(
              'Nothing in its history yet',
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
            AsyncValue(:final value?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final record in value.take(8))
                  MediaHistoryLine(record: record, scheme: scheme),
              ],
            ),
            AsyncValue(:final error?) => InlineErrorRetry(
              message: 'Could not read the history',
              error: error,
              service: copy.connection.service,
              instanceId: copy.connection.id,
              onRetry: () => ref.invalidate(
                mediaRadarrHistoryProvider((
                  connectionId: copy.connection.id,
                  movieId: copy.movieId,
                )),
              ),
            ),
            _ => const ShimmerPlaceholder(height: 36),
          },
        ],
      ],
    );
  }
}

/// What Request says and may do on a page: the title's state in Seerr, the
/// control's words, and what the account may ask.
typedef _Request = ({
  SeerrRequestGate gate,
  SeerrRequestWords words,
  GateVerdict verdict,
  ({String label, Uri url})? watch,
});

/// One line under the lead that says where a title stands: a 7 dot in its
/// tone, or the backlog's ring, then the sentence.
class _StateLine extends StatelessWidget {
  const _StateLine(this.text, {this.tone});

  final String text;

  /// The dot's tone; null draws the ring of something not there yet.
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final tone = this.tone;
    final color = tone == null
        ? room.inkTertiary
        : statusToneColor(Theme.of(context).colorScheme, tone);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone == null ? null : color,
              border: tone == null
                  ? Border.all(color: color, width: 1.4)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppType.meta
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
        ),
      ],
    );
  }
}
