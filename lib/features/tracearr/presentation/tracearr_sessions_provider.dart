import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

/// The streams one Tracearr connection sees, for the session plumbing the
/// media servers share (`streamSessionsForProvider`) to read.
///
/// The connection in view collapses onto [tracearrLiveProvider], the one list
/// Live and the Overview draw, so a stream is the same row, counted once,
/// wherever it is read; any other connection asks its own client. An empty
/// [instanceId] is the connection in view.
final tracearrStreamsForProvider =
    FutureProvider.family<TracearrStreams, String>((ref, instanceId) {
      final lens =
          ref.watch(activeInstanceProvider(ServiceKey.tracearr))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(tracearrLiveProvider.future);
      }
      return ref.watch(tracearrClientForProvider(instanceId)).getStreams();
    }, retry: noProviderRetry);
