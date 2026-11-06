/// What the Home reads again while it is on screen: the downloads and who
/// is watching, every [homeLiveInterval], and the storage every
/// [homeStorageInterval].
///
/// Only those, and only while their modules are on: the rest of the Home is
/// read on open, on pull and on return, and a figure that changes by the
/// minute is not worth a server's time every thirty seconds. One exception:
/// a connection that did not answer is asked again on the same clock, and the
/// first answer reads the whole Home again (`homeRecoveryPollProvider`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/data/storage.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_sessions_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// How often the Home reads its live modules again while it is seen.
const homeLiveInterval = Duration(seconds: 30);

/// What Downloads draws from: every queue, and the lists the download
/// clients' own pages hold, which the queue reads for the lens's
/// connection and which nothing else drops while their pages are away.
final List<ProviderOrFamily> homeDownloadsSources = [
  allTorrentsProvider,
  transmissionTorrentsProvider,
  sabnzbdQueueProvider,
  nzbgetQueueProvider,
  nzbgetStatusProvider,
  servicesQueueProvider,
];

/// The lists the download clients' own pages hold: the part of
/// [homeDownloadsSources] a client page drops, and what the queue reads as it
/// stands (it does not watch them).
final List<ProviderOrFamily> downloadClientLists = [
  allTorrentsProvider,
  transmissionTorrentsProvider,
  sabnzbdQueueProvider,
  nzbgetQueueProvider,
  nzbgetStatusProvider,
];

/// Reads the queue again at once when a write succeeded whose follow-up
/// dropped one of a client's lists: pausing, resuming or removing from a
/// client's page shows on the Home's In flight, the rail's lights and the
/// window's decisions now, not at the next poll.
///
/// Called by the two action runners with what they were told to drop. A queue
/// read in flight is restarted rather than left: it began before the write,
/// and a person's action is rare, unlike a tick.
void readDownloadsAfterWrite(
  ProviderContainer container,
  Iterable<ProviderOrFamily> dropped,
) {
  if (dropped.any(downloadClientLists.contains)) {
    container.invalidate(servicesQueueProvider);
  }
}

/// What Now playing draws from, on every connection of every media server and
/// of Tracearr: its list is read again here, since its live feed runs only
/// while its own pages are on screen and the Home would otherwise draw what
/// it saw last.
final List<ProviderOrFamily> homeSessionsSources = [
  for (final service in mediaServers) streamBackendOf(service).sessions,
  tracearrLiveProvider,
  tracearrStreamsForProvider,
  streamSessionsForProvider,
  streamActivityProvider,
];

/// The poll that keeps Downloads and Now playing current, for the Home to
/// watch while it is the page on screen (`watchWhileLive`).
///
/// Asks only for the modules the person keeps on and whose services are set
/// up: with neither there is no timer at all.
final homeLivePollProvider = Provider.autoDispose<void>((ref) {
  final layout = ref.watch(homeLayoutProvider);
  bool live(HomeModule module) =>
      layout.isOn(module) &&
      ref.watch(
        currentSettingsProvider.select(
          (settings) => module.services.any(settings.isServiceConfigured),
        ),
      );
  // The pools change by the minute at most: their own, slower clock.
  if (live(HomeModule.storage)) {
    ref.gatedPoll(
      id: 'home.storage',
      interval: homeStorageInterval,
      onTick: () => ref.invalidate(homeStorageProvider),
    );
  }
  final downloads = live(HomeModule.downloads);
  final sessions = live(HomeModule.nowPlaying);
  if (!downloads && !sessions) return;
  ref.gatedPoll(
    id: 'home.live',
    interval: homeLiveInterval,
    // Each group read again only once its last read has answered: a slow
    // queue must not hold back who is watching, nor be thrown away.
    onTick: () {
      if (downloads) ref.readAgainUnlessInFlight(homeDownloadsSources);
      if (sessions) ref.readAgainUnlessInFlight(homeSessionsSources);
    },
  );
});

/// The poll that brings a Home back once its servers answer again, for the
/// Home to watch while it is the page on screen.
///
/// Every [homeLiveInterval], the connections the header counts as silent are
/// probed again, and nothing else: a server that stays down costs one status
/// call a tick. When a round brings one back, the Home reads everything again,
/// once, as a pull would: the modules that failed with it recover on their own
/// (a phone back on its VPN, 11/10), with no pull to find.
final homeRecoveryPollProvider = Provider.autoDispose<void>((ref) {
  // Nothing set up, nothing to hear from: no timer at all.
  final anything = ref.watch(
    currentSettingsProvider.select(
      (settings) => ServiceKey.values.any(settings.isServiceConfigured),
    ),
  );
  if (!anything) return;
  // Held, not watched: the clock outlives every change of the lights, and a
  // round that brings the last server back must still read the Home again.
  final lights = ref.listen(stackLightsProvider, (_, _) {});
  ref.gatedPoll(
    id: 'home.recover',
    interval: homeLiveInterval,
    onTick: () async {
      final silent = [
        for (final service in lights.read().silent)
          for (final id in ref.read(serviceInstanceIdsProvider(service)))
            (service: service, instanceId: id),
      ];
      if (silent.isEmpty) return;
      for (final key in silent) {
        ref.invalidate(instanceSummaryProvider(key));
      }
      final answers = await Future.wait([
        for (final key in silent)
          ref
              .read(instanceSummaryProvider(key).future)
              .then<ServiceSummary?>(
                (summary) => summary,
                onError: (_) => null,
              ),
      ]);
      if (!ref.mounted) return;
      if (answers.any((summary) => summary != null && !summary.didNotAnswer)) {
        ref
            .read(navigationRefreshProvider(NavigationSection.home).notifier)
            .state++;
      }
    },
  );
});
