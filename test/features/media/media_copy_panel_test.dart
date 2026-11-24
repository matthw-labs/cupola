import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/media/domain/media_copy_panel.dart';

const _record = {
  'id': 2,
  'title': 'Big.Buck.Bunny.2008.1080p.BluRay',
  'downloadClient': 'qBittorrent',
  'size': 2400000000,
  'sizeleft': 1200000000,
};

MediaCopyPanel _panel(
  MediaStatusInfo status, {
  bool monitored = true,
  Map<String, dynamic>? record,
  DateTime? searchedAt,
}) => mediaCopyPanel(
  name: 'Radarr',
  status: status,
  monitored: monitored,
  record: record,
  searchedAt: searchedAt,
);

void main() {
  test('stuck: the fault, who has it, the release, and the remedy', () {
    final panel = _panel(
      const MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.stalled,
        progress: 0.47,
        detail:
            'Big.Buck.Bunny.2008.1080p.BluRay: The download is stalled with no '
            'connections',
      ),
      record: _record,
    );
    expect(panel.headline, 'Stuck at 47%');
    // The release has its own line: what the arr said, without it.
    expect(
      panel.sentence,
      'Nothing is arriving. Radarr says: The download is stalled with no '
      'connections',
    );
    expect(panel.tone, StatusTone.warning);
    expect(panel.source, 'Radarr\u00A0· qBittorrent');
    expect(panel.release, 'Big.Buck.Bunny.2008.1080p.BluRay');
    expect(panel.actions, [
      MediaCopyAction.tryAnother,
      MediaCopyAction.removeDownload,
    ]);
    expect(
      panel.consequence,
      matches(
        RegExp(
          r'^Radarr is asked to find another release\. The 1\.1.GB so far stays\.$',
        ),
      ),
    );
  });

  test('failed, with what the arr said, and before the record arrives', () {
    final panel = _panel(
      const MediaStatusInfo(
        pipeline: MediaPipeline.failed,
        detail: 'The download is missing files',
      ),
    );
    expect(panel.headline, 'Failed');
    expect(
      panel.sentence,
      "This download won't finish. Radarr says: The download is missing files",
    );
    // Nothing arrived that it can count: no figure in the consequence.
    expect(
      panel.consequence,
      'Radarr is asked to find another release. Downloaded files stay.',
    );
    expect(panel.source, 'Radarr');
  });

  test('a blocked import is finished by hand', () {
    final panel = _panel(
      // A status word is no message: it is not quoted.
      const MediaStatusInfo(
        pipeline: MediaPipeline.importBlocked,
        detail: 'Warning',
      ),
      record: _record,
    );
    expect(
      panel.sentence,
      'The download is done; Radarr needs a hand importing it.',
    );
    expect(panel.headline, 'Needs a manual import');
    expect(panel.tone, StatusTone.warning);
    expect(panel.actions, [MediaCopyAction.finishImport]);
  });

  test('a download client that does not answer is red, with no remedy', () {
    final panel = _panel(
      const MediaStatusInfo(pipeline: MediaPipeline.clientUnavailable),
      record: _record,
    );
    expect(panel.headline, 'qBittorrent did not answer');
    expect(panel.tone, StatusTone.error);
    expect(panel.actions, isEmpty);
  });

  test('downloading draws its bar, and asks nothing', () {
    final panel = _panel(
      const MediaStatusInfo(
        pipeline: MediaPipeline.downloading,
        progress: 0.62,
      ),
      record: _record,
    );
    expect(panel.headline, 'Downloading\u00A0· 62%');
    expect(panel.tone, isNull);
    expect(panel.progress, 0.62);
    expect(panel.actions, isEmpty);
  });

  test('searching: when it asked, and the release to pick by hand', () {
    final panel = _panel(
      const MediaStatusInfo(availability: MediaAvailability.missing),
      searchedAt: DateTime(2026, 10, 4, 20, 53),
    );
    expect(panel.headline, 'In Radarr\u00A0· searching');
    expect(panel.status, 'Radarr asked your indexers at 20:53');
    expect(panel.busy, isTrue);
    expect(panel.actions, [MediaCopyAction.chooseRelease]);
  });

  test('missing, unmonitored, cutoff unmet and not out yet', () {
    final missing = _panel(
      const MediaStatusInfo(availability: MediaAvailability.missing),
    );
    expect(missing.headline, 'In Radarr\u00A0· missing');
    expect(missing.actions.first, MediaCopyAction.automaticSearch);

    final unmonitored = _panel(
      const MediaStatusInfo(availability: MediaAvailability.missing),
      monitored: false,
    );
    expect(unmonitored.headline, 'In Radarr\u00A0· not monitored');
    expect(unmonitored.actions.first, MediaCopyAction.monitor);

    expect(
      _panel(
        const MediaStatusInfo(availability: MediaAvailability.upgradable),
      ).headline,
      'In Radarr\u00A0· cutoff unmet',
    );
    final unreleased = _panel(
      const MediaStatusInfo(availability: MediaAvailability.unavailable),
    );
    expect(unreleased.headline, 'In Radarr\u00A0· not out yet');
    expect(unreleased.actions, isEmpty);
  });
}
