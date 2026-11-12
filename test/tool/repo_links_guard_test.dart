import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The project lives at **`github.com/matthw-labs/cupola`**: nothing the app
/// ships or the package metadata names points at the repository's old name.
///
/// The repository was renamed from `seekarr` when the app became Cupola.
/// GitHub redirects the old address, so a stale link keeps working and no
/// check turns red, until the old name is taken by another repository and the
/// app's own *GitHub* row opens somebody else's project.
void main() {
  const stale = 'github.com/matthw-labs/seekarr';

  test('pubspec.yaml names the repository by its current name', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains(stale)),
      reason: 'homepage, repository and issue_tracker point at $stale.',
    );
  });

  test('no file under lib/ links to the repository by its old name', () {
    final offenders = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            entity.readAsStringSync().contains(stale))
          entity.path,
    ];
    expect(offenders, isEmpty, reason: 'These files link to $stale.');
  });
}
