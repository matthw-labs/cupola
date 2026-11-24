import 'dart:isolate';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/list_mapping.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// Configuration for *arr service activity endpoints.
class ArrServiceConfig {
  /// API version string (e.g., 'v3' for Radarr/Sonarr, 'v1' for Lidarr)
  final String apiVersion;

  /// Sort key for wanted endpoints (e.g., 'airDateUtc' for Radarr/Sonarr, 'releaseDate' for Lidarr)
  final String sortKey;

  /// Extra query parameters required for cutoff endpoints.
  final Map<String, dynamic> cutoffParams;

  /// Embedded **parents** requested by the calendar endpoint.
  ///
  /// The calendar record is always the dated entity itself: a movie, an
  /// episode, an album, a book, so there is never anything to ask for that
  /// names the record's own type. What a service may need is the thing above
  /// it: Sonarr's series, Lidarr's artist, Readarr's author.
  final Map<String, dynamic> calendarParams;

  const ArrServiceConfig({
    required this.apiVersion,
    required this.sortKey,
    this.cutoffParams = const {},
    this.calendarParams = const {},
  });

  // No calendar params: `/api/v3/calendar` returns the movies themselves, so
  // there is nothing to embed. `includeMovie` is a *queue* parameter and was
  // dead weight here, with the matching `record['movie']` lookup that never
  // found anything on the presentation side.
  static const radarr = ArrServiceConfig(
    apiVersion: 'v3',
    sortKey: 'airDateUtc',
  );
  static const sonarr = ArrServiceConfig(
    apiVersion: 'v3',
    sortKey: 'airDateUtc',
    cutoffParams: {'includeEpisodeFile': true},
    calendarParams: {'includeSeries': true, 'includeEpisodeFile': true},
  );
  static const lidarr = ArrServiceConfig(
    apiVersion: 'v1',
    sortKey: 'releaseDate',
    calendarParams: {'includeArtist': true},
  );
  // The record *is* the book, so only the author is worth embedding:
  // `includeBook` was the same mistake as Radarr's `includeMovie`.
  static const readarr = ArrServiceConfig(
    apiVersion: 'v1',
    sortKey: 'releaseDate',
    calendarParams: {'includeAuthor': true},
  );
}

/// Row count above which list mapping moves off the main isolate.
///
/// Same number and the same reasoning as the qBittorrent torrent parse and the
/// Jellyfin item mapper: below it the isolate spawn costs more than the mapping
/// does. It matters most on `lookupItems`, which runs on the debounced global
/// search path and typically answers with under twenty rows.
const int arrIsolateMapThreshold = 200;

/// How many pages of one walk are asked at once (see `_fetchAllPages`).
///
/// Three, and not more: a page with its embeds is a heavy query on the
/// server's side, and the walk is a read the user did not ask for by name.
const int _pageWalkLanes = 3;

/// Maps a decoded list, moving to an isolate once the page is big enough to be
/// worth the port.
///
/// Top-level rather than a mixin method on purpose: the closure handed to
/// `Isolate.run` must capture only sendable values, and one written inside an
/// instance method can drag `this` (which holds an [ApiClient]) across the
/// boundary.
Future<List<T>> _mapArrItems<T>(
  List<dynamic> data,
  T Function(Map<String, dynamic>) fromJson,
) async {
  if (data.length <= arrIsolateMapThreshold) {
    return data.map((item) => fromJson(item as Map<String, dynamic>)).toList();
  }
  return Isolate.run(
    () => data.map((item) => fromJson(item as Map<String, dynamic>)).toList(),
  );
}

/// The mapper a list read hands to [ApiClient.getMappedList]: the same mapping
/// as [_mapArrItems], run where the body is decoded. Captures only [fromJson],
/// which is a top-level or static function at every call site.
DecodedListMapper _listMapperOf<T>(T Function(Map<String, dynamic>) fromJson) {
  return (decoded) => (decoded as List<dynamic>)
      .map((item) => fromJson(item as Map<String, dynamic>))
      .toList();
}

/// The records of a list read through [ApiClient.getMappedList]: the list the
/// transformer already mapped, or the raw JSON a fake or an injected Dio
/// answered with, mapped here.
Future<List<T>> _recordsOf<T>(
  Object? data,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (data is MappedList) return Future.value(data.value as List<T>);
  return _mapArrItems(data as List<dynamic>, fromJson);
}

/// Pages [from] to [to], at most [_pageWalkLanes] requests in flight, answered
/// in page order whichever finished first. [onPrefix] hears the pages in hand
/// from [from] on, in order, each time that run grows and the range is not yet
/// whole.
///
/// A page that fails fails the read, as it does in the sequential walk: the
/// error surfaces at once, no lane starts another request after it, and the
/// ones still in flight are answered into nothing (`Future.wait` listens to
/// every lane, so a second failure is not left unhandled).
Future<List<ArrRecordPage>> _fetchPageRange(
  Future<ArrRecordPage> Function(int page) fetchPage,
  int from,
  int to, {
  void Function(List<ArrRecordPage> inOrder)? onPrefix,
}) async {
  if (to < from) return const [];
  final pages = List<ArrRecordPage?>.filled(to - from + 1, null);
  var nextPage = from;
  var failed = false;
  var prefix = 0;

  Future<void> lane() async {
    while (!failed && nextPage <= to) {
      final page = nextPage++;
      try {
        pages[page - from] = await fetchPage(page);
      } catch (_) {
        failed = true;
        rethrow;
      }
      // Told when the pages from the first one on are all in hand, never of a
      // page that finished ahead of one before it: a list that grows downward.
      if (onPrefix != null) {
        final before = prefix;
        while (prefix < pages.length && pages[prefix] != null) {
          prefix++;
        }
        if (prefix > before && prefix < pages.length) {
          onPrefix([for (var i = 0; i < prefix; i++) pages[i]!]);
        }
      }
    }
  }

  await Future.wait([
    for (var i = 0; i < math.min(_pageWalkLanes, pages.length); i++) lane(),
  ], eagerError: true);
  return [for (final page in pages) page!];
}

/// One page of an \*arr paged endpoint: the rows, and how many rows there are.
///
/// Every paged \*arr endpoint answers with the same envelope:
/// `{page, pageSize, totalRecords, records}`, and for a long time this app
/// threw away three quarters of it. `getHistory` and the wanted and cutoff
/// readers each returned `response.data['records']` and nothing else, so **every count
/// derived from them was the size of the page, not the size of the set**: a
/// library with 340 missing episodes read "20 missing" on the Activity pill,
/// because 20 is the default page size. The number was not approximate, it was
/// answering a different question (*how many did we fetch*) and it happened to
/// look like an answer to the one the user asked.
///
/// [total] is nullable rather than defaulted to [records]`.length`, and that is
/// the point of the type: a server that does not send `totalRecords` (an older
/// build, a proxy that rewrites the body) has told us nothing about the size of
/// the set, and `records.length` would be the same lie with a fresh coat on it.
/// A caller that gets null must print a count it can defend: "20 shown", or
/// no count at all.
class ArrRecordPage {
  const ArrRecordPage({
    required this.records,
    required this.total,
    this.cutShort = false,
  });

  /// The rows on this page: exactly what the old `List<dynamic>` return was.
  final List<dynamic> records;

  /// How many records the server says exist across every page, or null when it
  /// did not say.
  ///
  /// From a walk across pages ([ArrActivityMixin.getQueuePage],
  /// [ArrActivityMixin.getBlocklistPage]) it can also be the walk's own count:
  /// a server that sends no `totalRecords` still ends its set with a short
  /// page, and the rows before it are then every row there is.
  final int? total;

  /// A walk across pages stopped before the end of the set, so [records] is
  /// not all of it.
  ///
  /// Two ends prove nothing, and both used to be returned as if they were the
  /// whole set: the walk gives up after fifty pages, and a full page with no
  /// `totalRecords` gives it no reason to ask for another. With [total] in
  /// hand the count still stands and only the rows are short; without it the
  /// rows are a floor, and a figure taken from them is `200+`, never `200`.
  /// Always false for a single page, which is one window by definition.
  final bool cutShort;

  /// [records] as string-keyed maps, anything that is not a map dropped: the
  /// shape every reader of a raw page maps them into first.
  List<Map<String, dynamic>> get recordMaps =>
      records.whereType<Map>().map(stringKeyMap).toList(growable: false);

  /// Reads the envelope, tolerating the shapes the four \*arr forks answer with.
  ///
  /// `totalRecords` arrives as an int from a healthy server, as a double through
  /// a JSON layer that widened it, and as a string through at least one reverse
  /// proxy that re-serialises bodies. Anything else is treated as *absent*
  /// rather than coerced, because a total we cannot read is exactly the case
  /// [total] is nullable for.
  factory ArrRecordPage.fromEnvelope(Object? data) {
    if (data is! Map) return const ArrRecordPage(records: [], total: null);
    return ArrRecordPage(
      records: (data['records'] as List<dynamic>?) ?? const [],
      total: switch (data['totalRecords']) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value),
        _ => null,
      },
    );
  }
}

/// Mixin providing shared activity endpoints and common service helpers for
/// *arr services (Radarr, Sonarr, Lidarr).
mixin ArrActivityMixin {
  /// The API client used for requests.
  ApiClient get client;

  /// The service configuration (API version, sort key).
  ArrServiceConfig get config;

  /// The \*arr's own health checks (`/health`), each with its level and its
  /// words. Not a list is not a healthy server: it throws, like the
  /// calendar.
  Future<List<ArrHealthCheck>> getHealth() async {
    final response = await client.get('/api/${config.apiVersion}/health');
    final data = response.data;
    if (data is! List) {
      throw const FormatException('The health checks are not a list');
    }
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) ArrHealthCheck.fromJson(item),
    ];
  }

  /// Fetches the download queue, page by page, **with its total and whether
  /// the walk reached the end**.
  ///
  /// The queue endpoint is paginated and defaults to a page size of 10, so a
  /// bare `/queue` call silently returns the first ten records, which is what
  /// made Activity's "Now" bucket show ten Sonarr rows however full the real
  /// queue was. Pages of 200 (the server-side cap) keep this to a single
  /// request in the common case, and only page on when a queue is genuinely
  /// enormous.
  ///
  /// The primitive, for the reason [getHistoryPage] is: anything that prints
  /// a figure reads this one, and a service's own embeds (`includeMovie`,
  /// `includeSeries`…) belong on an override of this method, which [getQueue]
  /// inherits through its delegation.
  Future<ArrRecordPage> getQueuePage({Map<String, dynamic>? queryParameters}) {
    return _fetchAllPages(
      'queue',
      extraParams: queryParameters ?? const {},
      pageSize: 200,
    );
  }

  /// The queue, records only. Delegates, so there is still one walk here.
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    final result = await getQueuePage(queryParameters: queryParameters);
    return result.records;
  }

  /// Fetches calendar records for the requested local date range.
  ///
  /// Calendar is a first-class tab for all four *arr clients. The response
  /// shape differs by product (movies, episodes, albums or books), so the
  /// shared transport intentionally preserves the raw maps and lets the
  /// presentation layer name the embedded record without inventing a model
  /// that only fits one product.
  Future<List<dynamic>> getCalendar({
    DateTime? start,
    DateTime? end,
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await client.get(
      '/api/${config.apiVersion}/calendar',
      queryParameters: {
        if (start != null) 'start': _calendarDate(start),
        if (end != null) 'end': _calendarDate(end),
        ...config.calendarParams,
        ...?queryParameters,
      },
    );
    // Not a list is not an empty calendar. A reverse proxy's HTML page used to
    // become `[]` here, and the page said "The next 30 days are clear" about a
    // server it had not heard from; the screen draws this throw as its fault.
    final data = response.data;
    if (data is! List) {
      throw const FormatException('The calendar answer is not a list');
    }
    return List<dynamic>.from(data);
  }

  /// Fetches one page of history, **with the envelope's total**.
  ///
  /// The primitive; [getHistory] is the same request with the total dropped on
  /// the floor. Anything that prints a figure: the Activity pills, a service
  /// readout: must come through here, because the other one can only say how
  /// many rows it happened to fetch.
  ///
  /// NOTE for whoever migrates the callers: Radarr and Sonarr hang their extra
  /// query parameters (`includeMovie`, `includeSeries`/`includeEpisode`) off an
  /// override of [getHistory], not of this method, so calling this one directly
  /// on those two services returns records without the embedded media. Move
  /// those overrides onto [getHistoryPage] (same body, same super call), and
  /// [getHistory] inherits them through the delegation below.
  Future<ArrRecordPage> getHistoryPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await client.get(
      '/api/${config.apiVersion}/history',
      queryParameters: {
        'page': page,
        'pageSize': pageSize,
        ..._historySort,
        ...?queryParameters,
      },
    );
    return ArrRecordPage.fromEnvelope(response.data);
  }

  /// Every record since [date], in one answer: `/history/since` has no
  /// pages, so what it returns is the whole of the window and a count over it
  /// is a total. [queryParameters] narrow it (`eventType`) and embed the media
  /// (`includeMovie`, `includeSeries`, `includeAlbum`), each fork by its own
  /// names.
  Future<List<dynamic>> getHistorySince(
    DateTime date, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await client.get(
      '/api/${config.apiVersion}/history/since',
      queryParameters: {
        'date': date.toUtc().toIso8601String(),
        ...?queryParameters,
      },
    );
    final data = response.data;
    return data is List ? data : const [];
  }

  /// Newest first, asked for rather than assumed.
  ///
  /// Every reader of a history page treats it as the most recent records: the
  /// Overviews' "today" sections and Activity's "Finished today" count the day
  /// off page one, and stop believing in it at the first record older than
  /// today. A request with no sort key gets whatever order that server build
  /// defaults to, and an oldest-first page would read as a day with nothing
  /// in it. The four forks share the names: `date`, `descending`.
  static const _historySort = {
    'sortKey': 'date',
    'sortDirection': 'descending',
  };

  /// Fetches recent history, records only.
  ///
  /// Kept at its original signature rather than widened in place: two \*arr
  /// services override it and half a dozen callers spread across features this
  /// change does not reach read it, and a return type that moved under them
  /// would be a refactor of the whole activity layer disguised as a bug fix.
  /// It delegates, so there is still exactly one request here.
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    final result = await getHistoryPage(
      page: page,
      pageSize: pageSize,
      queryParameters: queryParameters,
    );
    return result.records;
  }

  /// Walks [endpoint] page by page, and says how far it got.
  ///
  /// It used to return the rows alone, which threw the envelope's total away
  /// and hid both of the ends where a walk proves nothing: the last page it
  /// allows itself with the count still naming more, and a full page from a
  /// server that sends no count. A caller counting the rows stated either one
  /// as the whole set; [ArrRecordPage.cutShort] now says which it was.
  ///
  /// The first page goes alone, because only its envelope says how many pages
  /// there are. The rest are then asked [_pageWalkLanes] at a time, never all
  /// at once: each one is a query the server runs against its whole backlog,
  /// and a small NAS answers three together sooner than fifty in a heap.
  /// Whatever the batch did not settle (a count that grew under the walk) goes
  /// on one page at a time, as before.
  ///
  /// [onProgress], when given, hears the records in hand (a fresh list each
  /// time, in page order) after the first page and each time the pages after it
  /// extend the run, until the walk is whole; it is not told of the whole,
  /// which is the answer. A screen draws from it before the walk ends.
  Future<ArrRecordPage> _fetchAllPages(
    String endpoint, {
    Map<String, dynamic> extraParams = const {},
    int pageSize = 250,
    int maxPages = 50,
    void Function(List<dynamic> records)? onProgress,
  }) async {
    Future<ArrRecordPage> fetchPage(int page) async {
      final response = await client.get(
        '/api/${config.apiVersion}/$endpoint',
        queryParameters: {'page': page, 'pageSize': pageSize, ...extraParams},
      );

      // The same envelope reader the single-page getters use, rather than the
      // second copy of the parse that used to live here, one of which had
      // already drifted, coercing an unreadable total into `records.length`
      // where the other coerced it into a page-sized guess.
      return ArrRecordPage.fromEnvelope(response.data);
    }

    final records = <dynamic>[];
    int? total;
    // Pages 2 to however many the first one promised, in page order.
    var batch = const <ArrRecordPage>[];

    for (var page = 1; page <= maxPages; page++) {
      final settled = page - 2;
      final envelope = page > 1 && settled < batch.length
          ? batch[settled]
          : await fetchPage(page);
      records.addAll(envelope.records);
      total = envelope.total;

      // An empty page is the end of the set, whatever the count said.
      if (envelope.records.isEmpty) {
        return ArrRecordPage(records: records, total: total ?? records.length);
      }

      // A null total means the server did not say how many there are, so this
      // page is the last thing we can honestly claim to know about: stop rather
      // than walk on asking for pages we have no reason to believe exist. A
      // short page ended the set, so the walk has counted it; a full one may
      // have another behind it, and its rows are only a floor.
      if (total == null) {
        final full = envelope.records.length >= pageSize;
        return ArrRecordPage(
          records: records,
          total: full ? null : records.length,
          cutShort: full,
        );
      }

      if (records.length >= total) {
        return ArrRecordPage(records: records, total: total);
      }

      if (page == 1) {
        // Counted by what the server actually sent, not by the size asked for:
        // one that caps the page lower than requested still has its offsets
        // laid out by the cap.
        final last = math.min(
          maxPages,
          (total / envelope.records.length).ceil(),
        );
        if (onProgress != null) onProgress(List.of(records));
        batch = await _fetchPageRange(
          fetchPage,
          2,
          last,
          onPrefix: onProgress == null
              ? null
              : (pages) => onProgress([
                  ...records,
                  for (final page in pages) ...page.records,
                ]),
        );
      }
    }

    // Out of pages with the count still naming more: the count stands, and
    // the rows are short of it.
    return ArrRecordPage(records: records, total: total, cutShort: true);
  }

  /// Fetches all history records across all pages. [onProgress] hears the
  /// records in hand before the walk is whole (see `_fetchAllPages`).
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
    void Function(List<dynamic> records)? onProgress,
  }) async {
    final result = await _fetchAllPages(
      'history',
      extraParams: {..._historySort, ...?queryParameters},
      onProgress: onProgress,
    );
    return result.records;
  }

  Map<String, dynamic> _wantedParams({bool includeCutoffParams = false}) {
    return {
      'sortKey': config.sortKey,
      'sortDirection': 'descending',
      'includeSeries': true,
      if (includeCutoffParams) ...config.cutoffParams,
    };
  }

  /// Fetches the whole blocklist, with its total and whether the walk reached
  /// the end.
  ///
  /// Same pagination trap as the queue: no page size means the server answers
  /// with ten records and the rest of the blocklist never reaches the screen.
  Future<ArrRecordPage> getBlocklistPage() {
    return _fetchAllPages('blocklist', pageSize: 200);
  }

  /// Fetches one page of missing items (wanted), **with the envelope's total**.
  ///
  /// This is the one the "34 missing" figure has to come from. `wanted/missing`
  /// defaults to 20 rows, so a count taken from the records alone said 20 for every
  /// library with more than twenty gaps in it: a number that is wrong in the
  /// one direction that matters, since it makes a large backlog look small.
  /// [queryParameters] is where a service's own wanted embeds ride, and it has
  /// to be **here**, on the primitive, for the reason [getHistoryPage] gives:
  /// the records-only spelling delegates to this, so an override of this one
  /// reaches both, while an override of the records-only one leaves every caller
  /// that needs the envelope's total, which is every caller that prints a figure:
  /// holding records the embed would have filled. Lidarr's `includeArtist` is
  /// the live case: the Overview's backlog clause counts distinct artists over
  /// this page, and without the embed that set is empty on every real server.
  Future<ArrRecordPage> getMissingPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await client.get(
      '/api/${config.apiVersion}/wanted/missing',
      queryParameters: {
        'page': page,
        'pageSize': pageSize,
        ..._wantedParams(),
        ...?queryParameters,
      },
    );
    return ArrRecordPage.fromEnvelope(response.data);
  }

  /// Fetches all missing items across all pages.
  ///
  /// Takes [queryParameters] of its own rather than inheriting the page
  /// primitive's: it walks `_fetchAllPages` directly, so an override that only
  /// covered [getMissingPage] would miss it, and this is the spelling
  /// Activity's Wanted tab reads.
  Future<List<dynamic>> getAllMissing({
    Map<String, dynamic>? queryParameters,
  }) async {
    final result = await getAllMissingPage(queryParameters: queryParameters);
    return result.records;
  }

  /// [getAllMissing] with the walk's own account of itself: the envelope's
  /// total and whether it stopped before the end ([ArrRecordPage.cutShort]).
  ///
  /// For a caller that *counts* what it read: a walk that gave up after its
  /// last page has only a floor, and a figure taken from the rows alone would
  /// state it as the whole. Throws when the server does not answer, as
  /// [getAllMissing] does.
  Future<ArrRecordPage> getAllMissingPage({
    Map<String, dynamic>? queryParameters,
  }) {
    return _fetchAllPages(
      'wanted/missing',
      extraParams: {..._wantedParams(), ...?queryParameters},
    );
  }

  /// Fetches one page of cutoff-unmet items, **with the envelope's total**.
  ///
  /// Degrades to an empty page with a **null** total rather than a zero one, and
  /// the distinction is the whole reason [ArrRecordPage.total] is nullable: not
  /// every \*arr fork serves `wanted/cutoff`, and a service that cannot answer
  /// the question has not answered "none". A zero here would put a confident
  /// "0 to upgrade" on a dashboard for a server that was never asked.
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await client.get(
        '/api/${config.apiVersion}/wanted/cutoff',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
          ..._wantedParams(includeCutoffParams: true),
          ...?queryParameters,
        },
      );
      return ArrRecordPage.fromEnvelope(response.data);
    } catch (_) {
      // Cutoff endpoint may not be available on all *arr variants.
      return const ArrRecordPage(records: [], total: null);
    }
  }

  /// Fetches all cutoff unmet items across all pages.
  ///
  /// Takes its own [queryParameters] for the reason [getAllMissing] does.
  Future<List<dynamic>> getAllCutoff({
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final result = await _fetchAllPages(
        'wanted/cutoff',
        extraParams: {
          ..._wantedParams(includeCutoffParams: true),
          ...?queryParameters,
        },
      );
      return result.records;
    } catch (_) {
      return [];
    }
  }

  /// Fetches all items from a list endpoint and maps them, in an isolate once
  /// the response is large enough to be worth one: answering `[]` when the
  /// list cannot be read.
  ///
  /// **Only for a caller that joins against the library and can go on
  /// without it**: a lookup by external id, an album cap in a queue join. There
  /// the library is one input among several, and the rest of the answer is
  /// still honest without it. A surface that *is* the library (a wall, an
  /// author list) has nothing else to show, and reading this made a dark
  /// server say "No items found". Those read [fetchAllItemsOrThrow].
  Future<List<T>> fetchAllItems<T>(
    String endpoint,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final response = await client.getMappedList(
        '/api/${config.apiVersion}/$endpoint',
        mapList: _listMapperOf(fromJson),
      );
      return await _recordsOf(response.data, fromJson);
    } catch (_) {
      return [];
    }
  }

  /// The same list, with a failed fetch allowed to reach the caller.
  ///
  /// The sibling of [fetchAllItems], and the pair is the point. Swallowing is
  /// right only for a join that can do without the library, and it is a
  /// fabrication for anything that *counts* or *is* the library, because an
  /// unreachable server and an empty library arrive as the same `[]`. Every
  /// figure derived
  /// from the swallowing read printed a confident zero for a question nobody
  /// answered: `Series 0 · Episodes 0/0 · Missing 0` on a Dashboard card,
  /// directly under an identity band whose own probe already read Unreachable.
  ///
  /// Callers that derive a figure read this one and turn the throw into
  /// [ServiceKpi.unavailable]'s em dash; the library walls read it too and
  /// render the throw as their fault state. Mapping is identical: straight through
  /// for a small list, through an isolate once it is worth the port, so the
  /// two differ in exactly one thing, which is whether the failure survives.
  Future<List<T>> fetchAllItemsOrThrow<T>(
    String endpoint,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await client.getMappedList(
      '/api/${config.apiVersion}/$endpoint',
      queryParameters: queryParameters,
      mapList: _listMapperOf(fromJson),
    );
    return _recordsOf(response.data, fromJson);
  }

  /// Fetches a single item by id, or null if it cannot be read.
  ///
  /// Deliberately not routed through `Isolate.run`: one object costs less to
  /// map here than to ship across a port.
  Future<T?> fetchItem<T>(
    String endpoint,
    int id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final response = await client.get(
        '/api/${config.apiVersion}/$endpoint/$id',
      );
      return fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Fetches a single item by id, letting a failure reach the caller: a page
  /// built on the record says why it could not be read, and a record that is
  /// gone (404) is a failure like any other rather than an empty page.
  Future<T> fetchItemOrThrow<T>(
    String endpoint,
    int id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await client.get(
      '/api/${config.apiVersion}/$endpoint/$id',
    );
    return fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches a filtered list endpoint and maps it, letting failures propagate.
  ///
  /// Unlike [fetchAllItems] this does **not** degrade to `[]`: the episode,
  /// album and track lists behind it belong to detail screens that show the
  /// failure rather than an empty section.
  Future<List<T>> fetchListItems<T>(
    String endpoint,
    Map<String, dynamic> queryParameters,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await client.get(
      '/api/${config.apiVersion}/$endpoint',
      queryParameters: queryParameters,
    );
    final data = response.data as List<dynamic>;
    return data
        .map((item) => fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Searches by term using a lookup endpoint and maps the results.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded: global search re-runs every service leg on each debounced
  /// keystroke, and a discarded round should stop paying for itself rather than
  /// run to completion. Failures (cancellation included) degrade to an empty
  /// list, like every other browse path.
  /// [reportFailure] decides whether a dead server is allowed to look like an
  /// empty library.
  ///
  /// Swallowing is the right default for a search-as-you-type field inside one
  /// service: the user is mid-word, the box is theirs, and an error banner that
  /// appears and vanishes between keystrokes is noise. It is the wrong default
  /// for the global search, and with several connections per service it becomes
  /// actively misleading: "No Radarr · Away results" reads as "that library
  /// does not have it" when what happened is that the box is off. There the
  /// caller passes true and gets the throw, which its own section turns into a
  /// stated failure.
  Future<List<T>> lookupItems<T>(
    String endpoint,
    String term,
    T Function(Map<String, dynamic>) fromJson, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    if (term.isEmpty) {
      return [];
    }

    try {
      // As typed: Dio encodes query values itself. Encoding it here too sent
      // `tvdb%253A121361`, which Sonarr matches to nothing, and turned
      // `Game of Thrones` into a search for `Game%20of%20Thrones`.
      final response = await client.getMappedList(
        '/api/${config.apiVersion}/$endpoint',
        queryParameters: {'term': term},
        cancelToken: cancelToken,
        mapList: _listMapperOf(fromJson),
      );
      return await _recordsOf(response.data, fromJson);
    } catch (_) {
      if (reportFailure) rethrow;
      return [];
    }
  }

  /// Fetches release candidates for interactive search.
  ///
  /// Defaults to [kReleaseSearchReceiveTimeout] rather than the client default:
  /// the server fans out to every enabled indexer and answers only once the
  /// slowest one has, so this is the one arr endpoint that legitimately runs
  /// for minutes. The release-search runner passes the user's own ceiling
  /// instead, so the Settings value governs both transports.
  Future<List<dynamic>> fetchReleases(
    Map<String, dynamic> queryParameters, {
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    final response = await client.get(
      '/api/${config.apiVersion}/release',
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      receiveTimeout: receiveTimeout ?? kReleaseSearchReceiveTimeout,
    );
    return response.data as List<dynamic>;
  }

  /// Describes the release-search request without performing it.
  ///
  /// For the Phase 2 background transport, which runs the request in native code
  /// and therefore needs a URL and headers rather than this client.
  ({Uri url, Map<String, String> headers}) releaseSearchRequest(
    Map<String, dynamic> queryParameters,
  ) {
    final base = client.baseUrl.endsWith('/')
        ? client.baseUrl.substring(0, client.baseUrl.length - 1)
        : client.baseUrl;
    return (
      url: Uri.parse('$base/api/${config.apiVersion}/release').replace(
        queryParameters: {
          for (final entry in queryParameters.entries)
            entry.key: '${entry.value}',
        },
      ),
      headers: client.headers,
    );
  }

  /// Asks for the service's own status and returns the raw response, so a caller
  /// can read *who answered* from the headers.
  ///
  /// The cheapest endpoint that is guaranteed to exist and to travel the full
  /// path, which is the point: the interesting information is the `server` and
  /// `cf-ray` headers a reverse proxy or CDN adds on the way back, not the body.
  Future<Response<dynamic>> probeHeaders() {
    return client.get('/api/${config.apiVersion}/system/status');
  }

  /// Asks this server to read a release or file name with its own parser:
  /// `GET /api/v3/parse?title=` on Radarr and Sonarr, `/api/v1/parse` on
  /// Lidarr.
  ///
  /// The answer echoes `title` and carries the parser's reading
  /// (`parsedMovieInfo`, `parsedEpisodeInfo`, `parsedAlbumInfo`) when it could
  /// read the name, and the library item it matched (`movie`, `series` and
  /// `episodes`, `artist` and `albums`) when it holds one. A failure travels:
  /// a server that did not answer has recognised nothing.
  Future<Map<String, dynamic>> parseTitle(String title) async {
    final response = await client.get(
      '/api/${config.apiVersion}/parse',
      queryParameters: {'title': title},
    );
    final data = response.data;
    return data is Map ? stringKeyMap(data) : const <String, dynamic>{};
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> fetchQualityProfiles() async {
    try {
      final response = await client.get(
        '/api/${config.apiVersion}/qualityprofile',
      );
      final data = response.data as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// The quality profiles, with a failed read allowed to reach the caller: a
  /// sheet that offers them must not read a server that did not answer as one
  /// with none to offer.
  Future<List<Map<String, dynamic>>> fetchQualityProfilesOrThrow() async {
    final response = await client.get(
      '/api/${config.apiVersion}/qualityprofile',
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('The server answered without its profiles');
    }
    return data.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  /// Fetches the root folders this server is configured to file media under.
  ///
  /// Unlike [fetchQualityProfiles], a failure here travels. The two are read
  /// side by side by the add sheet, and an empty list from this one is a
  /// sentence: "this server has nowhere to put it", that the sheet renders
  /// as a dead end. Swallowing the error would make an unreachable server say
  /// exactly that, which is the mistake `lookupItems` used to make: offline
  /// and empty became the same answer.
  Future<List<Map<String, dynamic>>> fetchRootFolders() async {
    final response = await client.get('/api/${config.apiVersion}/rootfolder');
    final data = response.data as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  /// How many of this server's indexers an automatic search asks: the ones
  /// with automatic search on. Null when the server did not answer, and the
  /// add sheet then says "your indexers" with no figure.
  Future<int?> countSearchingIndexers() async {
    try {
      final response = await client.get('/api/${config.apiVersion}/indexer');
      final data = response.data;
      if (data is! List) return null;
      return data
          .whereType<Map>()
          .where((indexer) => indexer['enableAutomaticSearch'] == true)
          .length;
    } catch (_) {
      return null;
    }
  }

  /// Updates an item's quality profile.
  Future<void> updateItemProfile(
    String resourcePath,
    int itemId,
    int qualityProfileId,
  ) async {
    final response = await client.get(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
    );
    final item = response.data as Map<String, dynamic>;
    item['qualityProfileId'] = qualityProfileId;
    await client.put(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
      data: item,
    );
  }

  /// Sets [fields] on an item, read whole first and put back whole: the
  /// \*arr replace the record they are sent.
  Future<void> updateItemFields(
    String resourcePath,
    int itemId,
    Map<String, Object?> fields,
  ) async {
    final response = await client.get(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
    );
    final item = response.data as Map<String, dynamic>;
    item.addAll(fields);
    await client.put(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
      data: item,
    );
  }

  /// Updates an item's monitored state.
  Future<void> updateItemMonitored(
    String resourcePath,
    int itemId,
    bool monitored,
  ) async {
    final response = await client.get(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
    );
    final item = response.data as Map<String, dynamic>;
    item['monitored'] = monitored;
    await client.put(
      '/api/${config.apiVersion}/$resourcePath/$itemId',
      data: item,
    );
  }

  /// Grabs a specific release for download.
  Future<void> grabReleaseByGuid({
    required String guid,
    required int indexerId,
  }) async {
    await client.post(
      '/api/${config.apiVersion}/release',
      data: {'guid': guid, 'indexerId': indexerId},
    );
  }

  /// Removes a record from the download queue.
  ///
  /// The activity surfaces were read-only until now: this mixin exposed five
  /// getters and no mutation, so a user who found a stalled download in Cupola
  /// had to open the service's own web UI to do anything about it.
  ///
  /// [removeFromClient] also deletes the download from the connected client
  /// (qBittorrent, SABnzbd…) rather than only from the \*arr queue.
  /// [blocklist] additionally records the release so the same one is not grabbed
  /// again, which, combined with a fresh search, is how a retry is expressed in
  /// the \*arr API. There is no dedicated "retry" endpoint.
  Future<void> removeFromQueue(
    int id, {
    bool removeFromClient = true,
    bool blocklist = false,
    bool? skipRedownload,
  }) async {
    await client.delete(
      '/api/${config.apiVersion}/queue/$id',
      queryParameters: {
        'removeFromClient': removeFromClient,
        'blocklist': blocklist,
        'skipRedownload': ?skipRedownload,
      },
    );
  }

  /// Removes a release from the blocklist, allowing it to be grabbed again.
  Future<void> deleteBlocklistItem(int id) async {
    await client.delete('/api/${config.apiVersion}/blocklist/$id');
  }
}

/// A bare `YYYY-MM-DD` in the caller's **local** date, which is what the *arr
/// calendars expect: the server parses it in its own timezone, and a user
/// asking about today means their today.
String _calendarDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// One of an \*arr's health checks (`/health`).
class ArrHealthCheck {
  const ArrHealthCheck({
    required this.source,
    required this.level,
    required this.message,
  });

  factory ArrHealthCheck.fromJson(Map<String, dynamic> json) => ArrHealthCheck(
    source: stringOrNull(json['source']) ?? '',
    level: (stringOrNull(json['type']) ?? '').toLowerCase(),
    message: stringOrNull(json['message']) ?? '',
  );

  /// The check that raised it, e.g. `RootFolderCheck`.
  final String source;

  /// `ok`, `notice`, `warning` or `error`, lowercased.
  final String level;

  /// The \*arr's own words.
  final String message;

  /// An error stops the \*arr's work (a root folder gone, no download client
  /// it can reach); a warning or a notice is news it shows on its own page.
  bool get isError => level == 'error';
}
