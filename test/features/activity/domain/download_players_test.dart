import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The way from the grab to the server may end on any media server.
void main() {
  test('the players a download step may name are the media servers', () {
    expect(downloadPlayers, mediaServers);
  });
}
