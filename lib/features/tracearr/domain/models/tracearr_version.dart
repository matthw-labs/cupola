/// A Tracearr version, comparable.
///
/// Tracearr spells it with a leading `v` (`v3.1.4`) while the rest of the
/// services we talk to do not, so the parse accepts both. We compare numbers,
/// never strings: `v3.10.0` is newer than `v3.9.0`.
final class TracearrVersion implements Comparable<TracearrVersion> {
  const TracearrVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = '',
  });

  /// `v3.1.4`, `3.1.4`, `v3.1` and `v3.2.0-beta.1`; null for anything else.
  static TracearrVersion? tryParse(String? text) {
    if (text == null) return null;
    final match = _shape.firstMatch(text.trim());
    if (match == null) return null;
    return TracearrVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3) ?? '0'),
      preRelease: match.group(4) ?? '',
    );
  }

  static final RegExp _shape = RegExp(
    r'^[vV]?(\d{1,6})\.(\d{1,6})(?:\.(\d{1,6}))?(?:[-+]([0-9A-Za-z.\-+]+))?$',
  );

  final int major;
  final int minor;
  final int patch;

  /// What follows a `-`, empty for a release. A pre-release sorts below the
  /// release it precedes.
  final String preRelease;

  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(TracearrVersion other) {
    final byNumbers = [
      major.compareTo(other.major),
      minor.compareTo(other.minor),
      patch.compareTo(other.patch),
    ].firstWhere((order) => order != 0, orElse: () => 0);
    if (byNumbers != 0) return byNumbers;
    if (preRelease == other.preRelease) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    return preRelease.compareTo(other.preRelease);
  }

  bool operator >=(TracearrVersion other) => compareTo(other) >= 0;

  bool operator >(TracearrVersion other) => compareTo(other) > 0;

  bool operator <(TracearrVersion other) => compareTo(other) < 0;

  bool operator <=(TracearrVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is TracearrVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  /// Without the `v`: it is the form a remedy prints ("install 3.2.0").
  @override
  String toString() =>
      '$major.$minor.$patch${isPreRelease ? '-$preRelease' : ''}';
}
