import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/settings/data/route_probe.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Re-tests every saved connection, at once.
///
/// **One command with two triggers, deliberately.** "Test all" in Settings and
/// ⌘R on the Settings tab are the same sentence, *ask every server again*,
/// and the moment they are two implementations they start disagreeing about
/// what "every" means: the button would refresh the services and the shortcut
/// the connections, or one would miss the second Radarr. So the set is defined
/// here, once, and both callers spend it.
///
/// Both families are invalidated because they answer different questions and
/// neither implies the other. [serviceDiagnosisProvider] folds a service across
/// its connections and is what every row in the list reads;
/// [instanceDiagnosisProvider] is per connection and is what the open form
/// reads. Refreshing only the first would leave a form that is mid-edit showing
/// a verdict from before the test the user just asked for.
///
/// Invalidation rather than an imperative re-probe: the providers already know
/// how to diagnose, only a live watcher needs an answer, and a service nobody
/// is looking at should not cost a round trip. So this is cheap on a settings
/// pane showing three rows and cheap on one showing eighteen.
///
/// Returns the number of connections that will be re-tested, so the caller can
/// say what it just did: a command whose only feedback is a spinner appearing
/// somewhere below the fold is a command the user presses twice.
int testAllConnections(WidgetRef ref) {
  final connections = ref.read(currentSettingsProvider).configuredInstances;

  // A test is the person asking every server again, so a qBittorrent sign-in
  // its client is holding as refused is sent once more: once per press, never
  // on a refresh. Without this the rows would re-read the held refusal and
  // "Test all" could never show a password fixed at the server.
  liftQbittorrentRefusals(ref, connections.map((instance) => instance.id));
  // A connection with an address away is knocked at both again: the readout
  // of one that answered at neither waits on the knock, and the moment an
  // address answers its route moves there and the red goes with it.
  unawaited(ref.read(routeProbeProvider).probeAll());
  ref.invalidate(serviceDiagnosisProvider);
  for (final instance in connections) {
    ref.invalidate(instanceDiagnosisProvider(instance.id));
  }

  return connections.length;
}

/// What [testAllConnections] just did, in words.
///
/// Here rather than at the call sites for the reason the whole connection
/// vocabulary lives in one place: the button and the shortcut must not announce
/// the same command two different ways.
String testAllConnectionsAnnouncement(int connections) => switch (connections) {
  0 => 'Nothing to test yet, no connection is set up.',
  1 => 'Testing the one connection…',
  _ => 'Testing all $connections connections…',
};
