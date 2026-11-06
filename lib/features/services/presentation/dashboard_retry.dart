/// What a Retry on the Dashboard has to drop for a service to be asked again.
///
/// Every Retry on this page used to re-read an answer already in the cache.
/// The region Retry invalidated `serviceSummaryProvider`, which only delegates
/// to the probe it awaits, and the merge, which awaits client providers that
/// keep a failure until somebody drops them (`retry: noProviderRetry`); the
/// alert band re-probed the connection and left every region's sources where
/// they were. So the probe could come back answering while "did not answer"
/// stayed under In flight, the qBittorrent rows stayed missing and the card
/// stayed at `—`: recovery only showed after a pull-to-refresh.
///
/// One function, so the band, the regions and the refresh drop the same set.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/features/discover/domain/library_calendar.dart'
    show CalendarKind;
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/data/storage.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/route_probe.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// The providers the Dashboard's merged regions read from [service] and that
/// keep an answer of their own: what has to be dropped for that service's
/// part of In flight and of Needs a decision to be read again.
///
/// The \*arrs are absent on purpose: their queue and their history are read
/// straight off their clients inside [servicesQueueProvider] and
/// [servicesArrHistoryProvider], so dropping those merges is their re-read.
List<ProviderOrFamily> dashboardSourcesOf(ServiceKey service) =>
    switch (service) {
      ServiceKey.qbittorrent => [allTorrentsProvider],
      ServiceKey.transmission => [transmissionTorrentsProvider],
      ServiceKey.sabnzbd => [sabnzbdQueueProvider],
      ServiceKey.nzbget => [nzbgetQueueProvider, nzbgetStatusProvider],
      // The lens's list, every other Seerr's, which the region reads too, and
      // the waiting page Requests on the Home counts from.
      ServiceKey.seerr => [
        requestRowsProvider,
        requestRowsForProvider,
        pendingRequestsForProvider,
      ],
      // The status list *is* the failing-indexer list; the indexers name them.
      ServiceKey.prowlarr => [
        prowlarrIndexerStatusProvider,
        prowlarrIndexersProvider,
      ],
      ServiceKey.dockge => [dockgeStackListProvider],
      ServiceKey.nginxProxyManager => [npmCertificatesProvider],
      ServiceKey.radarr ||
      ServiceKey.sonarr ||
      ServiceKey.lidarr ||
      ServiceKey.readarr ||
      ServiceKey.bazarr ||
      ServiceKey.truenas ||
      ServiceKey.unraid ||
      ServiceKey.jellyfin ||
      ServiceKey.plex ||
      ServiceKey.emby ||
      // Its four sources are the rail's own (`serviceKpiSources`), dropped with
      // the figures; it feeds no merged region of the Dashboard.
      ServiceKey.tracearr => const [],
    };

/// Asks [services] again, everywhere the Dashboard shows them: the probe of
/// each connection, the stack card's figures and the sources those figures
/// fold, and every region that reads them.
///
/// Only [services]. Re-checking the whole stack would throw away a dozen good
/// answers to re-fetch the ones that failed.
void retryDashboardServices(WidgetRef ref, Iterable<ServiceKey> services) {
  final asked = services.toSet();
  if (asked.isEmpty) return;
  for (final service in asked) {
    final ids = ref.read(serviceInstanceIdsProvider(service));
    // A Retry is the person asking again, so a qBittorrent sign-in a
    // connection's client is holding as refused is sent once more. Only here,
    // beside the failure: a pull that re-reads the page never lifts it.
    if (service == ServiceKey.qbittorrent) liftQbittorrentRefusals(ref, ids);
    // A connection neither of whose addresses answered is knocked at both
    // again: the moment one answers, its route moves there and the silence
    // said of both goes with it.
    final unanswered = ref.read(unansweredConnectionsProvider);
    for (final id in ids.where(unanswered.contains)) {
      unawaited(ref.read(routeProbeProvider).probe(id));
    }
    // The probe itself, one entry per connection. `serviceSummaryProvider`
    // only delegates to these, so invalidating it alone rebuilt a wrapper that
    // awaited the same cached answer.
    for (final id in ids) {
      ref.invalidate(
        instanceSummaryProvider((service: service, instanceId: id)),
      );
    }
    ref.invalidate(serviceSummaryProvider(service));
    ref.invalidate(serviceKpiProvider(service));
    ref.invalidate(serviceSignalPairProvider(service));
    ref.invalidate(foldedServiceKpisProvider(service));
    ref.invalidate(foldedServiceSignalPairProvider(service));
    // What the card's figures fold: without these the KPI rebuilt from the
    // failure its source was still holding.
    for (final source in serviceKpiSources(service)) {
      ref.invalidate(source);
    }
    for (final source in dashboardSourcesOf(service)) {
      ref.invalidate(source);
    }
  }
  // Keyed on the connection, so it cannot be narrowed to these services by
  // key, and a retry that left the fleet's figures cached would redraw the
  // recovered card with the numbers from the outage.
  ref.invalidate(serviceKpiForProvider);

  // The merges that read the \*arrs off their clients, and the decision
  // sources that read anything else, each only when it reads one of these.
  bool reads(DecisionSource source) => source.services.any(asked.contains);
  if (reads(DecisionSource.queue)) ref.invalidate(servicesQueueProvider);
  if (reads(DecisionSource.history)) {
    ref.invalidate(servicesArrHistoryProvider);
  }
  for (final source in DecisionSource.values) {
    if (reads(source)) ref.invalidate(dashboardDecisionSourceProvider(source));
  }

  // What the Home's other modules read of these, each keeping an answer of
  // its own: Arrived's week, Coming up's calendar, Continue watching's
  // resume, Storage's pools. Left cached, a Retry from Needs you brought the service back and
  // left those modules saying it did not answer.
  if (asked.any(_arrivalSources.contains)) {
    ref.invalidate(servicesArrivalsProvider);
  }
  if (asked.any((service) => CalendarKind.of(service) != null)) {
    ref.invalidate(calendarSourceProvider);
    ref.invalidate(libraryCalendarProvider);
  }
  if (asked.contains(ServiceKey.truenas) || asked.contains(ServiceKey.unraid)) {
    ref.invalidate(homeStorageProvider);
  }
  if (asked.any((service) => service.isMediaServer)) {
    ref.invalidate(homeResumeProvider);
  }
}

/// The libraries Arrived reads its week from.
const _arrivalSources = {
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
};
