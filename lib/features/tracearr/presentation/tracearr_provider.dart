import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/data/connection_providers.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';

/// The size of the page a count that cannot be summed is read at. A page that
/// came back with another following has counted rows, not the set, so its
/// figure is a floor (`25+`).
const int kTracearrCountPage = 25;

/// Tracearr's client for the connection the app is looking through, and for a
/// named one.
///
/// This is the one place a [TracearrClient] is built from a connection, so the
/// transport's pin, access headers and `onlyAtHome` reach it here (ADR-6).
/// Widgets check `isServiceConfigured(ServiceKey.tracearr)` before they watch
/// anything below: the client throws "not configured" otherwise.
final _tracearr = ConnectionProviders<TracearrClient>.transport(
  ServiceKey.tracearr,
  create: (ref, transport) => TracearrClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    pinnedCertFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
    onlyAtHome: transport.onlyAtHomeOf(ServiceKey.tracearr),
  ),
  close: (client) => client.close(),
);

final tracearrClientProvider = _tracearr.lens;

final tracearrClientForProvider = _tracearr.forConnection;

/// The health read: the one answer that names Tracearr's version.
///
/// `noProviderRetry` on every read below, because the figures, the Overview's
/// sections and the Dashboard's rail await these inside handlers written to
/// carry on without a source that is down; ten backed-off retries held in
/// front of that handler would be the rail sitting in its skeleton.
final tracearrHealthProvider = FutureProvider<TracearrHealth>(
  (ref) => ref.watch(tracearrClientProvider).getHealth(),
  retry: noProviderRetry,
);

/// The servers Tracearr watches, with what it last saw of each.
final tracearrServersProvider = FutureProvider<TracearrServers>(
  (ref) => ref.watch(tracearrClientProvider).getServers(),
  retry: noProviderRetry,
);

/// What is playing now, with the summary above it. Read again by a pull; the
/// live event stream that keeps it moving is a later lot's.
final tracearrStreamsProvider = FutureProvider<TracearrStreams>(
  (ref) => ref.watch(tracearrClientProvider).getStreams(),
  retry: noProviderRetry,
);

/// Today's plays and watch time.
///
/// Asked with no time zone: the device's name for it is an abbreviation and
/// Tracearr wants an IANA one, so its day is cut at UTC midnight.
final tracearrTodayProvider = FutureProvider<TracearrToday>(
  (ref) => ref.watch(tracearrClientProvider).getToday(),
  retry: noProviderRetry,
);

/// The first page of people, for what only counts or glances at them. The
/// Users tab pages its own list (`tracearrUsersListProvider`).
final tracearrUsersProvider = FutureProvider<TracearrPage<TracearrUser>>(
  (ref) => ref.watch(tracearrClientProvider).getUsers(),
  retry: noProviderRetry,
);

/// The first page of violations nobody has looked at.
///
/// Its length is a **floor** when [TracearrPage.hasMore]: the API pages and
/// gives no total, so a full first page counted rows and not the set.
final tracearrUnseenViolationsProvider =
    FutureProvider<TracearrPage<TracearrViolation>>(
      (ref) => ref
          .watch(tracearrClientProvider)
          .getViolations(
            pageSize: kTracearrCountPage,
            filter: const TracearrViolationFilter.unseen(),
          ),
      retry: noProviderRetry,
    );

/// The unseen count as a figure: the rows when the page is the last, a floor
/// when another follows. Pure, so the rail and the Overview read one rule.
({int count, bool isFloor}) tracearrUnseenCount(
  TracearrPage<TracearrViolation> page,
) => (count: page.items.length, isFloor: page.hasMore);
