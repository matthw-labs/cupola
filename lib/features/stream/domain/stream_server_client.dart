/// What the Stream feature needs from a media server, regardless of which one.
///
/// The dashboard, the library browse and the item detail are written against this
/// and never against Jellyfin or Plex directly, so the two implementations can
/// keep their genuinely different mechanics: ticks against milliseconds, one
/// `PlayMethod` against three independent `*Decision` fields, an impersonating
/// admin key against a single-perspective token, without leaking either into a
/// widget.
///
/// Errors follow the project convention: a missing configuration throws
/// `ServiceNotConfigured`, which `AsyncValueWidget` answers with
/// `NotConfiguredPlaceholder`. Write actions surface their failure so
/// the UI can report them.
///
/// Reads come in two kinds, and which kind a read is decides whether it may
/// degrade. **A read that is the whole of a surface throws**: [getSessions]
/// and [getLibraries] are each the only thing their board has to show, so a
/// swallowed failure there is not a quieter page, it is a false one: "Nobody
/// is watching right now" about a server nobody could ask. **A read that fills
/// one slot of a page otherwise drawn** may degrade to `[]`/`null`: a count
/// beside a card, a search group, the item a detail link resolves to. A
/// degraded answer there has to be a gap the page can state honestly, never a
/// figure.
library;

import 'package:dio/dio.dart' show CancelToken;

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_library_page.dart';
import 'package:cupola/features/stream/domain/models/stream_search_group.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

/// A viewer whose watch state a library can be read through.
class StreamViewer {
  final String id;
  final String name;

  const StreamViewer({required this.id, required this.name});
}

/// A title the viewer finished, and when.
///
/// An episode stands for its series: what someone watched is the series, and
/// that is what a recommendation is asked of.
typedef StreamWatched = ({StreamItem item, DateTime playedAt});

/// Resolved artwork: the URL plus whatever headers authenticate it.
///
/// A record rather than a bare URL because the credential must stay in a header
/// wherever it can. `ImageUtils.extractPosterUrl` can only emit `X-Api-Key`, and
/// putting a token in the query string leaks it into `CachedNetworkImage`'s cache
/// key, which is also the reason Plex's `/photo/:/transcode` proxy is only used
/// where its `url=` parameter genuinely forces the issue, and then with a
/// 48-hour delegation token rather than the user's own.
typedef StreamImageSource = ({String url, Map<String, String>? headers});

abstract interface class StreamServerClient {
  /// Reachability probe returning the server version.
  ///
  /// Deliberately the endpoint that does not *require* a credential on either
  /// server (`/System/Info/Public`, `/identity`), so that "the box is down" and
  /// "the token is wrong" cannot arrive as the same error: the single most
  /// common Stream misconfiguration, and the one a generic timeout hides.
  ///
  /// Note the precise claim: not that no credential is *sent*. Both clients set
  /// their auth header in `BaseOptions`, so it travels here too. What makes the
  /// separation hold is the server side: Jellyfin marks the endpoint
  /// `[AllowAnonymous]`, so a rejected token cannot turn this into a failure,
  /// and [verifyCredential] is the call that answers the credential question.
  Future<String?> probeVersion();

  /// Whether the stored credential is accepted. Separate from [probeVersion].
  Future<bool> verifyCredential();

  /// Everything playing right now, most expensive first.
  ///
  /// Throws on a remote failure: an empty list is the server saying nobody is
  /// watching, and only the server may say it.
  Future<List<StreamSession>> getSessions();

  /// Stop one playback.
  ///
  /// Both servers only *dispatch* this: Jellyfin returns 204 meaning "sent to
  /// the client", which may ignore it, and Plex returns an empty body. Callers
  /// must re-read [getSessions] to confirm rather than trusting the status code.
  Future<void> stopSession(String sessionId);

  /// The libraries this server exposes.
  ///
  /// Throws on a remote failure, for the reason [getSessions] does.
  Future<List<StreamLibrary>> getLibraries();

  /// How many items one library holds, or null when the server would not say.
  ///
  /// **One call per library, and never on the list.** Both servers can answer a
  /// count only as its own request (`/Items?limit=0` reading `TotalRecordCount`,
  /// `X-Plex-Container-Size=0` reading `totalSize`), so folding it into
  /// [getLibraries] would turn one round trip into one per library on every
  /// dashboard load. That cost is the whole reason the count belongs to the
  /// pushed Libraries page and not to the Overview rows: the card renders
  /// complete without it and the number lands afterwards.
  ///
  /// Counted in whatever unit the library browses in: series for a TV library,
  /// not episodes, so the card cannot show a figure the grid then contradicts.
  ///
  /// Null on failure, per the read convention, and the caller prints "—" rather
  /// than 0: a count that could not be read is not a count of nothing.
  Future<int?> getLibraryItemCount(
    String libraryId, {
    CancelToken? cancelToken,
  });

  /// What this server holds matching [query], grouped the way it groups it.
  ///
  /// The two servers arrive at grouping from opposite directions and meet here:
  /// Jellyfin types every hint (`GET /Search/Hints`) and the client buckets
  /// them, Plex answers in hubs (`GET /hubs/search`) already grouped *and*
  /// ordered, so the page renders the order it is given rather than imposing
  /// one. See [StreamSearchGroup] for why an empty group survives.
  ///
  /// [limit]'s unit genuinely differs: it is a total on Jellyfin and per hub on
  /// Plex, which is why it has no shared default: null asks each client for the
  /// number that suits its own endpoint.
  ///
  /// **Throws when the server did not answer or answered with a failure**, so
  /// the one surface that asks (a global search lane) can say which, in its
  /// tone. Any list is an answer: empty groups, or none, mean the server was
  /// asked and nothing matched. It used to degrade to `[]`, which the lane
  /// could only read as a request that did not complete.
  Future<List<StreamSearchGroup>> search(
    String query, {
    int? limit,
    CancelToken? cancelToken,
  });

  /// One page of a library, whole, in [sort] order, with the paging envelope
  /// kept.
  ///
  /// [unplayedOnly] keeps what the viewer has not finished: a watch state, so
  /// on Jellyfin and Emby it needs [viewerId] (the API key has no user of its
  /// own) and answers [StreamLibraryPage.viewerRequired] without one; Plex
  /// ignores [viewerId], having only the token's own perspective. The whole
  /// shelf in any order is the same for everyone, and needs no viewer.
  /// [cancelToken] is part of the interface rather than an implementation extra:
  /// the project's convention is that list and search fetches are cancellable,
  /// and both clients had independently widened their overrides to add it. Left
  /// off here, every provider that wanted cancellation had to depend on the
  /// concrete `JellyfinClient` or `PlexClient`, which forfeits the one thing
  /// this interface exists for.
  ///
  /// The only way to a library's rows. A plain list of them, which the
  /// interface once offered beside this, could not say whether an empty result
  /// meant the library is empty, the request failed, or this particular page
  /// happened to be filtered down to nothing, and each of those needs a
  /// different thing on screen. See [StreamLibraryPage] for the two false
  /// claims that came out of collapsing them.
  ///
  /// Never throws. A failure is [StreamPageOutcome.failed]: the caller decides
  /// whether this is a retry affordance or a quiet gap.
  Future<StreamLibraryPage> getLibraryPage({
    required String libraryId,
    StreamLibrarySort sort = StreamLibrarySort.name,
    bool unplayedOnly = false,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  });

  // Deliberately no `hasViewer` here. "An unplayed shelf has no subject" is
  // already carried by [StreamLibraryPage.needsViewer], per request, where the
  // browse actually needs it, so a second, connection-wide spelling of the same
  // fact bought nothing and forced every implementer and test fake to declare a
  // member no caller read.

  /// One item at any depth.
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  });

  /// The page the series [seriesId] has, by the ids this server holds for it:
  /// what a season or an episode (`StreamItem.seriesId`) opens when it opens
  /// its series. One read of the series' own item, asking for its external
  /// ids (Jellyfin's `ProviderIds`, Plex's `Guid[]`), and the key is
  /// `MediaKey.ofStreamItem` of what came back: TMDB's id, else TVDB's.
  ///
  /// **The answer is checked, never taken on trust**: only the item that is
  /// [seriesId], and a series, names a page. A server that ignored the id and
  /// answered with the start of its library names none.
  ///
  /// Null when the server holds no id for the series, said something else, or
  /// did not answer: it fills the one slot of a tap that has the server's own
  /// page to fall back on, so no failure is told apart and none is thrown.
  /// Never retried: [cancelToken] ends it.
  Future<MediaKey?> getSeriesKey(String seriesId, {CancelToken? cancelToken});

  /// The page the movie or the series [titleId] has, read and checked as
  /// [getSeriesKey] reads a series': what a live session's title is known by
  /// to the arrs (`StreamSession.titleId`). Null when the server holds no id
  /// for it, said something else, or did not answer. Never retried:
  /// [cancelToken] ends it.
  Future<MediaKey?> getTitleKey(String titleId, {CancelToken? cancelToken});

  /// The children of a series, season or album.
  ///
  /// Throws on a remote failure: an empty list is an item with nothing
  /// inside, which is what the item page says of it.
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  });

  /// Every episode of the series [seriesId], specials included, with the
  /// viewer's watch state where there is a viewer: one read, for a title's
  /// page, numbered by season and episode.
  ///
  /// Throws on a remote failure: an empty list is a series with no episode
  /// on the server.
  Future<List<StreamItem>> getEpisodes(
    String seriesId, {
    String? viewerId,
    CancelToken? cancelToken,
  });

  /// The verified item, "not in the library" (the server answered with no
  /// rows), or "not verified" (rows came back and none is this title). **Throws
  /// when the server did not answer or answered with a failure**, that is
  /// neither of the other two, and the availability slot says it in its own
  /// words.
  Future<StreamExternalLookup> lookupByExternalId({
    String? tmdbId,
    String? tvdbId,
    String? imdbId,
    StreamItemKind? kind,
    String? title,
    int? year,
    CancelToken? cancelToken,
  });

  /// What the viewer started and did not finish, the most recently played
  /// first, at most [count] (a server may hand back titles nobody has
  /// started, so the caller asks for more than it draws and filters).
  ///
  /// Throws on a remote failure, for the reason [getSessions] does: Continue
  /// watching names a server that did not answer, and an empty list would say
  /// nothing is in progress there. A server whose resume is user-scoped and has
  /// no viewer chosen throws too; the caller asks who the viewer is before it
  /// asks this.
  Future<List<StreamItem>> getContinueWatching({
    required int count,
    CancelToken? cancelToken,
  });

  /// The next episode of each series the viewer is following, across the
  /// server, the most recently watched series first, at most [count].
  ///
  /// Throws like [getContinueWatching], and for the same reasons: a server
  /// that did not answer is not one where nothing is up next. Plex's on deck
  /// holds both halves; its next-up half is what has no position yet.
  Future<List<StreamItem>> getNextUp({
    required int count,
    CancelToken? cancelToken,
  });

  /// What the server added last, across its libraries: movies, and series by
  /// their newest episode, the latest first, at most [count]. The same for
  /// every viewer.
  ///
  /// Throws on a remote failure: an empty list is a server that added
  /// nothing.
  Future<List<StreamItem>> getRecentlyAdded({
    required int count,
    CancelToken? cancelToken,
  });

  /// What the viewer finished last, the latest first: movies, and series by
  /// their latest episode, each once, at most [limit].
  ///
  /// [viewerId] is required by Jellyfin, where the API key has no user of its
  /// own, and ignored by Plex, whose token is its user. Degrades to `[]`: it
  /// fills one shelf of a page drawn otherwise, and a shelf with nothing to
  /// say is not drawn.
  Future<List<StreamWatched>> getRecentlyWatched({
    String? viewerId,
    int limit = 5,
    CancelToken? cancelToken,
  });

  /// Household members whose watch state can be read.
  ///
  /// Returns a single-entry list on Plex: its token is its only viewer.
  /// Throws on a remote failure: an empty list is a server with nobody on it.
  Future<List<StreamViewer>> getViewers();

  /// Resolve artwork for an item or session poster path.
  ///
  /// **Synchronous, and that is a requirement rather than an optimisation.** A
  /// poster grid calls this once per tile during `build`; a `Future` would force
  /// every cell through a `FutureBuilder` and hand the grid a frame of empty boxes
  /// on every scroll. Both servers can answer it by string manipulation alone:
  /// Jellyfin composes `/Items/{id}/Images/Primary`, Plex either resolves a
  /// relative key or builds a `/photo/:/transcode` URL, so nothing here needs a
  /// round trip. If a future server ever does (a signed URL, say), it belongs
  /// behind a cache the client owns, not in this signature.
  StreamImageSource? imageFor(String posterPath, {int? width});

  void close();
}
