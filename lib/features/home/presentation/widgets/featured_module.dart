/// Featured: the one authored moment of the Home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/services/presentation/services_provider.dart'
    show arrivalsSinceProvider;
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/featured_last_known.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/arrived_module.dart'
    show openArrived;
import 'package:cupola/features/home/presentation/widgets/continue_watching_module.dart'
    show openResume;
import 'package:cupola/features/home/presentation/widgets/featured_pager.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/stream_web_url.dart';
import 'package:cupola/features/stream/presentation/play_with.dart';

/// Featured: up to three slides, what somebody was watching, the newest
/// arrival and what comes out today, moving on by themselves; the room takes
/// its light from the slide in front (`featuredRoomLightProvider`).
///
/// Absent while nothing is in progress, nothing arrived and nothing is out
/// today, and while every source it reads is silent: the modules below name
/// a server that did not answer. Never a failure of its own.
class HomeFeaturedModule extends ConsumerWidget {
  const HomeFeaturedModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!HomeModule.featured.services.any(settings.isServiceConfigured)) {
      return const SizedBox.shrink();
    }
    // The live slides, or until they come the last drawing's (a cold start),
    // cut to what is still true now.
    final read = ref.watchOrLastKnown(featuredProvider, featuredLastKnown);
    final live = read.live;
    final known = read.asOf;
    final now = ref.watch(calendarClockProvider)();
    final slides = switch (read.value) {
      final drawn? when known != null => featuredAsDrawn(
        drawn,
        now: now,
        since: ref.watch(arrivalsSinceProvider),
      ),
      final value => value,
    };
    Widget placed(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.slabY,
        AppSpacing.lg,
        0,
      ),
      child: child,
    );
    if (slides == null) {
      return live.hasError
          ? const SizedBox.shrink()
          : placed(const FeaturedSkeleton());
    }
    // Nothing to feature, live or as last drawn: no place is kept for it, so
    // a cold start whose drawing had none draws none rather than a skeleton
    // that would leave the page with a jump.
    if (slides.isEmpty) return const SizedBox.shrink();

    final view = ref.watch(featuredViewProvider);
    final views = ref.read(featuredViewProvider.notifier);
    return LastKnownMark(
      asOf: known,
      checking: !live.hasError,
      child: placed(
        FeaturedPager(
          pages: [
            for (final slide in slides)
              _pageOf(
                context,
                ref,
                slide,
                now: now,
                light: ref.watch(featuredLightProvider(slide.art.url)),
              ),
          ],
          initialIndex: view.index,
          onShown: views.show,
          onArtDrawn: views.drawn,
          live: watchPageActivity(context, ref).isLive,
          advances: ref.watch(featuredAdvancesProvider),
        ),
      ),
    );
  }

  FeaturedPage _pageOf(
    BuildContext context,
    WidgetRef ref,
    FeaturedSlide slide, {
    required DateTime now,
    required TitleLight? light,
  }) {
    final line = slide.line(now);
    final label = joinSpokenParts([slide.title, spokenFromDotted(line)]);
    final details = switch (slide) {
      FeaturedResume(:final row) => () => openResume(context, row),
      FeaturedArrival(:final entry) => () => openArrived(context, entry),
      FeaturedToday(:final event) => () => _openToday(context, event),
    };
    return FeaturedPage(
      title: slide.title,
      line: line,
      art: slide.art,
      label: label,
      onOpen: details,
      light: light,
      lead: switch (slide) {
        FeaturedResume(:final row) => FeaturedAction(
          'Resume',
          () => _play(
            context,
            ref,
            service: row.service,
            instanceId: row.instanceId,
            itemId: row.item.id,
            title: row.item.title,
          ),
          icon: Icons.play_arrow_rounded,
        ),
        FeaturedArrival(:final play?) => FeaturedAction(
          'Play',
          () => _play(
            context,
            ref,
            service: play.service,
            instanceId: play.instanceId,
            itemId: play.item.id,
            title: play.item.title,
          ),
          icon: Icons.play_arrow_rounded,
        ),
        _ => FeaturedAction('Details', details),
      },
      second: switch (slide) {
        FeaturedResume() => FeaturedAction('Details', details),
        FeaturedArrival(play: _?) => FeaturedAction('Details', details),
        FeaturedToday(downloading: true) => FeaturedAction(
          'Queue',
          () => context.go(ServiceRoutes.activity),
        ),
        _ => null,
      },
    );
  }
}

/// A slide of today's calendar opens its title's page; a record that names
/// no title, its service.
void _openToday(BuildContext context, CalendarEvent event) {
  if (event.target case CalendarMediaTarget(:final key, :final connectionId)) {
    context.openMedia(key, focus: connectionId);
    return;
  }
  context.go(ServiceRoutes.forService(event.kind.service));
}

/// Opens [itemId] in its server's own client, where it plays.
Future<void> _play(
  BuildContext context,
  WidgetRef ref, {
  required ServiceKey service,
  required String instanceId,
  required String itemId,
  required String title,
}) async {
  final server = ref.read(currentSettingsProvider).instanceById(instanceId);
  if (server == null) return;
  String? machineId;
  try {
    machineId = switch (service) {
      ServiceKey.plex => (await ref.read(
        plexCapabilitiesForProvider(instanceId).future,
      )).machineIdentifier,
      // Emby's link names the server too, and works when it does not answer.
      ServiceKey.emby => await ref.read(
        embyServerIdProvider(instanceId).future,
      ),
      _ => null,
    };
  } catch (_) {
    machineId = null;
  }
  if (!context.mounted) return;
  await playWith(
    context,
    ref,
    server: server,
    itemId: itemId,
    title: title,
    // The web client at the address the server is reached at now.
    webUrl: streamItemWebUrl(
      service: service,
      baseUrl: ref.read(connectionReachProvider(instanceId))?.url ?? '',
      itemId: itemId,
      serverId: machineId,
    ),
  );
}
