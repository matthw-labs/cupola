import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Home modules that read what a media server holds name their services as
/// a const literal (an enum argument cannot call a getter). This holds each
/// literal to the capability it stands for, so a new media server cannot be
/// added to the registry and silently left out of Now playing or Continue
/// watching.
void main() {
  Set<ServiceKey> mediaServersOf(HomeModule module) =>
      module.services.where((s) => s.isMediaServer).toSet();

  test('Now playing reads every service that says who is playing', () {
    expect(HomeModule.nowPlaying.services.toSet(), sessionServices.toSet());
    expect(HomeModule.nowPlaying.services.length, sessionServices.length);
  });

  test('Continue watching reads every media server and nothing else', () {
    expect(HomeModule.continueWatching.services.toSet(), mediaServers.toSet());
    expect(HomeModule.continueWatching.services.length, mediaServers.length);
  });

  test('Featured reads every media server, beside the arrs that feed it', () {
    expect(mediaServersOf(HomeModule.featured), mediaServers.toSet());
    expect(
      HomeModule.featured.services.where((s) => !s.isMediaServer).toSet(),
      {ServiceKey.radarr, ServiceKey.sonarr},
    );
  });
}
