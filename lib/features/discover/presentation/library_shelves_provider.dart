import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/collection_shelf.dart';
import 'package:cupola/features/discover/domain/library_shelves.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// Because you watched: what the household finished last, on any media
/// server, and TMDB's recommendations for it as Seerr relays them.
typedef WatchedShelf = ({String watched, List<MediaPreview> items});

/// A collection the operator is part way through, as Seerr knows it.
typedef CollectionInvitation = ({
  CollectionDetail detail,
  CollectionShelf shelf,
});

/// Whether the atrium has a media server to ask what was watched: one that
/// is set up and, where its watch state is a household member's
/// ([ServiceKeyExtension.needsViewerSelection]), has one chosen.
final hasWatchHistoryProvider = Provider<bool>((ref) {
  return mediaServers.any((service) {
    final configured = ref.watch(
      currentSettingsProvider.select((s) => s.isServiceConfigured(service)),
    );
    if (!configured) return false;
    if (!service.needsViewerSelection) return true;
    final viewer = ref.watch(activeInstanceProvider(service))?.viewerId;
    return (viewer ?? '').isNotEmpty;
  });
});

/// Null when nothing watched carries a TMDB id, or TMDB recommends nothing
/// for it: the shelf is drawn only where it has something to say. A media
/// server that does not answer reads as one with nothing watched.
final becauseYouWatchedProvider = FutureProvider<WatchedShelf?>((ref) async {
  if (!ref.watch(hasWatchHistoryProvider)) return null;
  final settings = ref.read(currentSettingsProvider);
  final servers = await Future.wait([
    for (final service in mediaServers)
      if (settings.isServiceConfigured(service))
        ref.watch(streamBackendOf(service).lensClient).getRecentlyWatched(),
  ]);
  final latest = latestRecommendable(servers);
  if (latest == null) return null;
  final items = await ref
      .watch(seerrServiceProvider)
      .getRecommendations(latest.mediaType, latest.tmdbId);
  if (items.isEmpty) return null;
  return (watched: latest.item.title, items: items);
}, retry: noProviderRetry);

/// Whether the atrium may invite the operator to complete a collection: the
/// shelf reads the lens's Radarr, which is not the requester's.
final mayCompleteCollectionsProvider = Provider<bool>((ref) {
  if (ref.watch(audienceProvider) != Audience.operator) return false;
  return ref.watch(
    currentSettingsProvider.select(
      (s) => s.isServiceConfigured(ServiceKey.radarr),
    ),
  );
});

/// The collection nearest to whole that still misses a movie, on the lens's
/// Radarr, and where each of its movies stands by Seerr. Radarr counts a
/// movie it has no file for yet, Seerr does not: the first three candidates
/// are read until one is on the server in part and, by Seerr's word, still
/// has something to do on its page: a movie to add, or a request to answer.
/// Movies only on their way leave nothing to do, and no invitation.
final completeTheCollectionProvider = FutureProvider<CollectionInvitation?>((
  ref,
) async {
  if (!ref.watch(mayCompleteCollectionsProvider)) return null;
  final collections = await ref.watch(radarrServiceProvider).getCollections();
  final numbering = await ref.watch(seerrNumberingProvider.future);
  for (final candidate in collectionsToComplete(collections).take(3)) {
    final detail = await ref.watch(
      collectionDetailProvider(candidate.tmdbId).future,
    );
    final shelf = CollectionShelf.of(detail, numbering: numbering);
    if (shelf.invitesCompletion) {
      return (detail: detail, shelf: shelf);
    }
  }
  return null;
}, retry: noProviderRetry);
