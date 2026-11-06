import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

/// How many of the latest violations the Overview shows.
const int kTracearrOverviewViolations = 3;

/// How many titles of the week the Overview shows.
const int kTracearrOverviewTop = 3;

/// The latest violations, whether or not anybody has looked, newest first.
///
/// The Overview's own read: its section is the newest few and the unseen ones
/// among them say so, where the rail's figure counts only the unseen.
final tracearrLatestViolationsProvider =
    FutureProvider<TracearrPage<TracearrViolation>>(
      (ref) => ref
          .watch(tracearrClientProvider)
          .getViolations(pageSize: kTracearrOverviewViolations),
      retry: noProviderRetry,
    );

/// The titles most watched in the last seven days, movies and series together
/// by their plays, or null when this Tracearr has no such read.
///
/// `top-media` came with Tracearr 3.1.4, and an older one that is still new
/// enough for everything else answers it with a 404. That is not a failure of
/// the section: the section is left out, and nothing says it is empty.
final tracearrTopWeekProvider = FutureProvider<List<TracearrTopMedia>?>((
  ref,
) async {
  final client = ref.watch(tracearrClientProvider);
  try {
    final pages = await Future.wait([
      client.getTopMedia(
        mediaType: TracearrTopMediaType.movie,
        days: 7,
        pageSize: kTracearrOverviewTop,
      ),
      client.getTopMedia(
        mediaType: TracearrTopMediaType.show,
        days: 7,
        pageSize: kTracearrOverviewTop,
      ),
    ]);
    final titles = [for (final page in pages) ...page.items]
      ..sort((a, b) => b.plays.compareTo(a.plays));
    return titles.take(kTracearrOverviewTop).toList(growable: false);
  } on DioException catch (error) {
    if (error.response?.statusCode == 404 &&
        error.error is! AccessGatewayAnswer) {
      return null;
    }
    rethrow;
  }
}, retry: noProviderRetry);
