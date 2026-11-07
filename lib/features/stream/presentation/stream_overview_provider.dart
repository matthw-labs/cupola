/// What the media-server Overview reads, and the pure functions that shape it.
///
/// One file for both servers, like every other Stream surface: the screen is
/// parameterised by `ServiceKey` and the difference between Jellyfin and Plex
/// lives in what each client can actually answer, never in a fork of the page.
///
/// Every windowing rule here is a top-level pure function taking an explicit
/// `now`, so a boundary (a scan timestamp from a host whose clock runs ahead,
/// an hour-old scan against a day-old one) is tested without a clock and
/// without a container.
///
/// ## What the board asks for that this Overview does not draw
///
/// The four artboards (`HomeJellyfin`, `HomeJellyfinMobile`, `HomePlex`,
/// `HomePlexMobile`) were drawn against an ideal server. What is built here is
/// the intersection of that drawing and what `JellyfinClient` / `PlexClient`
/// genuinely fetch. Overview stays intentionally compact; dedicated tabs own
/// the records that do not belong on the landing page, and unsupported figures
/// remain absent rather than fabricated:
///
///  * **Bandwidth / egress** (`8.4 Mb/s`, `18 GB · 24 h`): neither server
///    reports measured outbound throughput. Jellyfin carries a bitrate only
///    while transcoding and Plex's `Session.bandwidth` is a reservation made by
///    its streaming brain; summing them adds two units and calls the result
///    traffic. `service_kpi_provider.dart` already refuses this figure for the
///    same reason, and per-session rates stay on the session cards where
///    `StreamSession.bitrateIsNominal` can say what they are.
///  * **Recently added** (`14 this week`): a server-wide recent list needs
///    `GET /Users/{userId}/Items/Latest` (Jellyfin) or
///    `GET /library/recentlyAdded` (Plex). Neither is implemented, and the one
///    lens that exists is per library: folding it would be one request per
///    library on every load *and* would still have nothing to sort by, since
///    `StreamItem` carries no `addedAt`. A rail ordered by nothing, claiming to
///    be ordered by arrival, is the fake this file exists to avoid.
///  * **Continue watching, on Jellyfin**: `GET /Users/{userId}/Items/Resume`.
///    Plex has `/hubs/continueWatching` and therefore gets the rail; Jellyfin's
///    equivalent is unbuilt, and the per-library `continueWatching` lens is not
///    a substitute for the same two reasons as above.
///  * **Scheduled tasks and the activity log** (Jellyfin) belong to the Tasks
///    and Activity tabs. The Activity tab uses live sessions because the
///    historical activity-log endpoint is not part of this client.
///  * **Activities, devices and playlists** (Plex) belong to their dedicated
///    tabs. Activities uses live sessions because Plex has no supported
///    historical activity endpoint here.
///  * **`idle 4 h · last: nadia · 18:40`** (Plex): the idle line needs watch
///    history, `GET /status/sessions/history/all`.
///  * **Remote access, mapped port, transcoder hardware, cache size, uptime**
///    (the Plex *Server* region): `GET /:/prefs` and
///    `GET /statistics/resources`. What `GET /` does answer is drawn.
///  * **Per-library item counts** (`1 020`, `86`), decision 21: a count is its
///    own request per library on both servers, and that cost belongs to the
///    Libraries tab, not to a page the user lands on every time they open the
///    service.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart' show formatRelativeDateTime;
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';

/// Posters on the On deck rail.
///
/// Six, the number the desktop board draws, and the number
/// `/hubs/continueWatching` is asked for, so the rail is not a sample taken
/// from a longer answer that nothing then reports.
const int streamOnDeckPreviewLimit = 6;

/// Rows the Libraries peek draws before the header's census is the only place
/// the rest are reported.
const int streamShelfPeekLimit = 3;

// ─── The shelf: the rooms on the server, and what is happening to them ──────

/// The glyph a library wears, by what it holds.
///
/// One switch for the whole feature: the Libraries tab draws the same rooms as
/// cards and the Overview peek draws three of them as rows, and two copies of
/// this mapping would be two vocabularies for the same shelf.
IconData streamLibraryGlyph(StreamLibraryKind kind) => switch (kind) {
  StreamLibraryKind.movies => Icons.movie_outlined,
  StreamLibraryKind.shows => Icons.tv_outlined,
  StreamLibraryKind.music => Icons.library_music_outlined,
  StreamLibraryKind.photos => Icons.photo_library_outlined,
  StreamLibraryKind.other => Icons.folder_outlined,
};

/// The glyph one item wears on its plate when it has no artwork, in the same
/// vocabulary as [streamLibraryGlyph]: a season has no poster of a film.
IconData streamItemGlyph(StreamItemKind kind) => switch (kind) {
  StreamItemKind.movie => Icons.movie_outlined,
  StreamItemKind.series ||
  StreamItemKind.season ||
  StreamItemKind.episode => Icons.tv_outlined,
  StreamItemKind.album => Icons.album_outlined,
  StreamItemKind.track => Icons.music_note_outlined,
  StreamItemKind.other => Icons.folder_outlined,
};

/// What one Libraries peek row is about.
///
/// Two states, and the tones are the point of the enum. A scan in progress is
/// **informational**: the server is doing exactly what it was asked to do, and
/// painting it amber would put a working library in the same colour as a broken
/// import. A library at rest is **neutral**: it is the state of the shelf, not
/// an event, and nothing about it needs a decision.
enum StreamShelfKind {
  /// A library being scanned right now.
  scanning(StatusTone.info),

  /// A library the server is not currently touching.
  atRest(StatusTone.neutral);

  const StreamShelfKind(this.tone);

  final StatusTone tone;
}

/// One row of the Libraries peek: a room on the server.
@immutable
class StreamShelfRow {
  const StreamShelfRow({
    required this.kind,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final StreamShelfKind kind;

  /// The glyph for what the room holds: [streamLibraryGlyph].
  final IconData icon;

  /// The subject: the library's own name, as the server spells it.
  final String title;

  /// The evidence: what it holds and what is happening to it, and **never the
  /// title again**. A library called "Movies" whose kind is `movies` gets no
  /// kind in its detail, because `Movies` over `Movies` is a row that reports
  /// itself twice and a screen reader that says the word twice in one sentence.
  /// It is empty when the server said nothing beyond the name, which is the
  /// resting state of every Jellyfin library.
  final String detail;

  StatusTone get tone => kind.tone;

  /// The row as one sentence, with the layout's `·` back as a comma; a screen
  /// reader either names the dot or drops it depending on the user's
  /// punctuation setting, and neither reading is a sentence.
  String get spoken =>
      joinSpokenParts([title, if (detail.isNotEmpty) spokenFromDotted(detail)]);
}

/// How long ago a scan finished, as of [now].
///
/// A thin wrapper on [formatRelativeDateTime] for one reason, and it is a real
/// one on self-hosted hardware: a NAS whose clock runs ahead of the phone hands
/// back a `scannedAt` in the future, and the shared formatter answers that
/// honestly with `in 4 min`, which under a heading reading *Last scan* is not
/// a sentence. A future timestamp is clamped to `just now`, exactly as
/// `formatSampleAge` clamps its own, rather than being dropped: the scan did
/// happen, only the two clocks disagree about when.
String streamScanAgeLabel(DateTime scannedAt, {required DateTime now}) {
  final local = scannedAt.toLocal();
  final reference = now.toLocal();
  if (!local.isBefore(reference)) return 'just now';
  return formatRelativeDateTime(local, now: reference);
}

/// The second line of a peek row: what the room holds, then what is being done
/// to it.
///
/// The kind is dropped when it merely restates the name. A scan in progress
/// hides the last scan's age, because while something is being scanned *when
/// the last one finished* is the stale half of the same fact.
///
/// **A library with no `lastScannedAt` is never called "never scanned".** That
/// field is null both for a Plex section that has genuinely never been scanned
/// *and* for every Jellyfin library, which exposes no per-library timestamp at
/// all: one endpoint's silence and one server's absence arrive as the same
/// null. Saying "never scanned" would be a fabrication on every Jellyfin
/// install, so that half of the line is simply absent.
String streamShelfDetail(StreamLibrary library, {required DateTime now}) {
  final kind = library.kind.label;
  final named = kind.toLowerCase() == library.name.trim().toLowerCase();
  final scannedAt = library.lastScannedAt;
  return joinDisplayParts([
    if (!named) kind,
    if (library.isRefreshing)
      'Scanning'
    else if (scannedAt != null)
      'Scanned ${streamScanAgeLabel(scannedAt, now: now)}',
  ]);
}

/// What the Libraries region draws under its header: the rooms themselves.
///
/// **A peek, not the list.** The Libraries tab one tap away draws every room as
/// a destination; this draws [limit] of them as a readout, so a page the user
/// lands on every time they open the service says what is on the shelf instead
/// of only whether a broom is being pushed across it. Naming the rooms costs
/// nothing (`getLibraries` already answered names and kinds), and it is the
/// difference between a region with substance and the single "No scan running"
/// line that was Jellyfin's Overview at rest, which is the *majority* state of
/// a home server rather than an edge case.
///
/// **Scans come first**, so a rescan is never pushed off the peek by the
/// alphabet; everything after keeps the server's own order, which is the order
/// the Libraries tab lists them in.
///
/// **Rows are capped at [limit] and the census is not.** The header's subtitle
/// is built from the whole list by [streamLibrariesCensus], so a full rescan of
/// nine libraries reads `9 scanning` above three rows rather than reporting
/// three and hiding six: counting inside a capped preview and then stating the
/// result as a total is the defect this batch keeps finding.
List<StreamShelfRow> streamShelfRows(
  List<StreamLibrary> libraries, {
  required DateTime now,
  int limit = streamShelfPeekLimit,
}) {
  final ordered = [
    ...libraries.where((library) => library.isRefreshing),
    ...libraries.where((library) => !library.isRefreshing),
  ];
  return List.unmodifiable([
    for (final library in ordered.take(limit))
      StreamShelfRow(
        kind: library.isRefreshing
            ? StreamShelfKind.scanning
            : StreamShelfKind.atRest,
        icon: streamLibraryGlyph(library.kind),
        title: library.name,
        // The kind and the scan age, never a percentage: `StreamLibrary`
        // carries no progress figure; Jellyfin's `RefreshProgress` is dropped
        // at the parse boundary and Plex's lives on another endpoint, so the
        // board's `62%` has no source behind it.
        detail: streamShelfDetail(library, now: now),
      ),
  ]);
}

/// The Libraries header's census, or null when nothing behind it answered.
///
/// [libraries] is null while the list is in flight and after it failed; null
/// here reads "—" on the header, never 0. An empty list is the server's own
/// answer: `getLibraries` throws on a remote failure, so `[]` can only arrive
/// from a server that answered and holds nothing. It used to swallow that
/// failure, and this function took the reachability probe as a second
/// argument to tell the two apart: a guess that read "did not answer" over a
/// real empty shelf whenever the probe had not landed yet.
String? streamLibrariesCensus({required List<StreamLibrary>? libraries}) {
  if (libraries == null) return null;
  final scanning = libraries.where((library) => library.isRefreshing).toList();
  return streamLibrariesSummary(
    total: libraries.length,
    // Naming the first of several would imply the others were idle; the
    // summary prints a count in that case instead.
    scanningName: scanning.length == 1 ? scanning.first.name : null,
    scanningCount: scanning.length,
  );
}

// ─── On deck (Plex only) ────────────────────────────────────────────────────

/// The rail, from whatever `/hubs/continueWatching` answered.
///
/// An item with no id is dropped rather than drawn: the tile's whole purpose is
/// to open the thing, and a poster that routes nowhere is a control that fails.
/// Capped at [limit] for the same reason the request asks for [limit]: the
/// header states no count, so nothing here is a sample presented as a total.
///
/// **A repeated id is dropped too, and that is not hygiene.**
/// `PlexClient._itemsFromHubs` concatenates `Metadata` across every hub the
/// response carries: the method exists in that shape because
/// `/hubs/continueWatching` answers as a hub list on some builds, with no
/// dedupe of its own, so an episode sitting in both Continue watching and On
/// deck arrives twice under one `ratingKey`. Two tiles for one episode is the
/// visible half; the other half is two Heroes and a poster the user has already
/// half-watched offered as if it were two different things.
List<StreamItem> streamOnDeckPreview(
  List<StreamItem> items, {
  int limit = streamOnDeckPreviewLimit,
}) {
  final seen = <String>{};
  final kept = <StreamItem>[];
  for (final item in items) {
    if (kept.length == limit) break;
    final id = item.id.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    kept.add(item);
  }
  return List.unmodifiable(kept);
}
