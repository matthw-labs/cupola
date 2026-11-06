import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/settings/data/connection_test_command.dart';

/// "Test all": the button half of the command ⌘R is the other half of.
///
/// One widget rather than one per surface: the summary card and the connections
/// header are the same command in two places, and a second copy is where the
/// two would start testing different sets or saying different things afterwards.
///
/// It announces through a snack because the work is invisible: the rows below
/// re-enter their checking state, but on a list of eighteen the ones that
/// changed are usually off screen, and a command with no acknowledgement is a
/// command people press twice.
class TestAllConnectionsButton extends ConsumerWidget {
  const TestAllConnectionsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () {
        final message = testAllConnectionsAnnouncement(testAllConnections(ref));
        SnackBarHelper.info(context, message);
      },
      // The label is the accessible name; the hint says what "all" covers,
      // since the button sits beside a count that a screen reader has already
      // moved past.
      child: Semantics(
        hint: 'tests every saved connection again',
        child: const Text('Test all'),
      ),
    );
  }
}
