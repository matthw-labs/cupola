import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Retry of a media server's row asks that connection again, whichever
/// media server it is: a Retry that fell through a switch did nothing.
void main() {
  const key = MediaKey.movie(133701);

  for (final service in mediaServers) {
    testWidgets('a failed ${service.name} row reads its connection again', (
      tester,
    ) async {
      var reads = 0;
      late WidgetRef ref;
      final connection = ServiceInstance(
        id: 'media-1',
        service: service,
        label: '',
        url: 'http://media.lan:8096',
        credential: 'k',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaStreamCopyProvider.overrideWith((ref, source) async {
              reads++;
              throw StateError('not answering');
            }),
          ],
          child: Consumer(
            builder: (context, r, _) {
              ref = r;
              r.watch(
                mediaStreamCopyProvider((
                  key: key,
                  connectionId: connection.id,
                )),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      expect(reads, 1);

      retryMediaRow(
        ref,
        key,
        MediaConnectionRow<Object?>(connection, const MediaReadingWaiting()),
      );
      await tester.pump();
      await tester.pump();
      expect(reads, 2);
    });
  }
}
