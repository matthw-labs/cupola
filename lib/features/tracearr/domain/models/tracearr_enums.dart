/// The kind of media server Tracearr watches.
///
/// Every enum in this file has an explicit `unknown` case: Tracearr adds values
/// between releases (a fourth server type, a new media type) and an unseen word
/// must reach the screen as "unknown", never as a crash or a dropped page.
enum TracearrServerType {
  plex,
  jellyfin,
  emby,
  unknown;

  static TracearrServerType fromWire(Object? value) => switch (value) {
    'plex' => plex,
    'jellyfin' => jellyfin,
    'emby' => emby,
    _ => unknown,
  };
}

/// What Tracearr last saw when it asked a server.
enum TracearrServerStatus {
  up,
  down,
  unknown;

  static TracearrServerStatus fromWire(Object? value) => switch (value) {
    'up' => up,
    'down' => down,
    _ => unknown,
  };
}

/// Why a server is not `up`, when Tracearr says.
///
/// `unauthorized` is the one worth a remedy of its own: Tracearr reaches the
/// server but its token there was refused, and only the owner can fix that in
/// Tracearr.
enum TracearrServerReason {
  unauthorized,
  unknown;

  static TracearrServerReason? fromWire(Object? value) => switch (value) {
    null => null,
    'unauthorized' => unauthorized,
    _ => unknown,
  };
}

enum TracearrMediaType {
  movie,
  show,
  season,
  episode,
  track,
  live,
  photo,
  trailer,
  unknown;

  static TracearrMediaType fromWire(Object? value) => switch (value) {
    'movie' => movie,
    'show' => show,
    'season' => season,
    'episode' => episode,
    'track' => track,
    'live' => live,
    'photo' => photo,
    'trailer' => trailer,
    _ => unknown,
  };
}

/// The `media_type` the history route filters on.
///
/// Measured on Tracearr 3.1.4: `show` and `season` are a 400 here, and
/// `unknown` is accepted. Kept apart from [TracearrMediaType] (what a row
/// says) so an invalid filter cannot be written.
enum TracearrHistoryMediaType {
  movie,
  episode,
  track,
  live,
  photo,
  trailer,
  unknown,
}

/// The `media_type` of top-media, which takes titles, not episodes: only these
/// two, anything else is a 400.
enum TracearrTopMediaType { movie, show }

enum TracearrStreamState {
  playing,
  paused,
  stopped,
  unknown;

  static TracearrStreamState fromWire(Object? value) => switch (value) {
    'playing' => playing,
    'paused' => paused,
    'stopped' => stopped,
    _ => unknown,
  };
}

/// What a server does with one track of a stream.
///
/// `copy` is a direct stream: the container is rewrapped and the track is left
/// alone.
enum TracearrDecision {
  directPlay,
  copy,
  transcode,
  unknown;

  static TracearrDecision? fromWire(Object? value) => switch (value) {
    null => null,
    'directplay' => directPlay,
    'copy' => copy,
    'transcode' => transcode,
    _ => unknown,
  };
}

enum TracearrSeverity {
  low,
  warning,
  high,
  unknown;

  static TracearrSeverity fromWire(Object? value) => switch (value) {
    'low' => low,
    'warning' => warning,
    'high' => high,
    _ => unknown,
  };

  /// The word the API filters on (`severity`), or null for [unknown].
  String? get wire => this == unknown ? null : name;

  /// Higher is worse; an unknown severity ranks with the lowest so it never
  /// outshouts a known one.
  int get rank => switch (this) {
    high => 3,
    warning => 2,
    low => 1,
    unknown => 0,
  };
}

/// The window of the `media/{ref}/watchers` read.
enum TracearrWindow {
  allTime('all_time'),
  last30('last_30'),
  last7('last_7'),
  unknown('');

  const TracearrWindow(this.wire);

  /// The value the API takes and answers with.
  final String wire;

  static TracearrWindow fromWire(Object? value) {
    for (final window in values) {
      if (window != unknown && window.wire == value) return window;
    }
    return unknown;
  }
}

/// The sort of a top-media read.
enum TracearrTopSort {
  plays('plays'),
  watchTime('watch_time'),
  viewers('viewers');

  const TracearrTopSort(this.wire);

  final String wire;
}
