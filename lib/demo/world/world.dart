/// The fictional household the profiles live in: World A of the design
/// brief, so a test and a design board name the same things: Radarr and
/// Radarr 4K, Sprite Fright at 62 %, Big Buck Bunny stuck at 47 %, Anna and
/// Luca waiting on Seerr.
///
/// Rows are built here rather than read from `test/fixtures/` because they
/// join across services: a Radarr queue row and its qBittorrent torrent share
/// a download id, a Seerr request names the Radarr server that takes it, and
/// because their times are relative to the network's `now`, so "2 h ago"
/// renders as "2 h ago" on whatever day the suite runs. Shapes that carry no
/// title (TrueNAS `auth.me`, NPM `users/me`, Unraid `me`, Plex `/identity`)
/// come from `test/fixtures/` as they are.
library;

/// Addresses, from the brief: everything on `nas.home.arpa`, one port each.
/// The six World-B services live on `tower.home.arpa`.
abstract final class WorldHosts {
  static const radarr = 'http://nas.home.arpa:7878';
  static const radarr4k = 'https://nas.home.arpa:7879';
  static const sonarr = 'http://nas.home.arpa:8989';
  static const sonarrAnime = 'http://nas.home.arpa:8990';
  static const lidarr = 'http://nas.home.arpa:8686';
  static const prowlarr = 'http://nas.home.arpa:9696';
  static const bazarr = 'http://nas.home.arpa:6767';
  static const qbittorrent = 'http://nas.home.arpa:8080';
  static const sabnzbd = 'http://nas.home.arpa:8085';
  static const seerr = 'http://nas.home.arpa:5055';
  static const jellyfin = 'http://nas.home.arpa:8096';
  static const dockge = 'https://nas.home.arpa:5001';
  static const truenas = 'https://nas.home.arpa';
  static const plex = 'http://nas.home.arpa:32400';
  static const transmission = 'http://nas.home.arpa:9091';

  /// A second Jellyfin, at the cabin: in no profile, for a test that adds it
  /// with `ConfigProfile.withConnection`: two of a media server.
  static const jellyfinCabin = 'http://cabin.home.arpa:8096';

  /// The cabin's Seerr, likewise in no profile: two Seerr, each with its own
  /// requests.
  static const seerrCabin = 'http://cabin.home.arpa:5055';

  /// The cabin's Plex, likewise in no profile: two of the other media server.
  static const plexCabin = 'http://cabin.home.arpa:32400';

  /// A second standard Radarr that only Seerr knows, for the archive: P6's
  /// Seerr offers it beside the default, so a request can be sent there.
  static const radarrArchive = 'http://nas.home.arpa:7880';

  /// A second Lidarr beside the first, for the vinyl rips: in no profile, for
  /// a test that adds it.
  static const lidarrVinyl = 'http://nas.home.arpa:8687';

  /// A friend's Seerr, outside the household, where the operator has an
  /// account of his own. P9's second Seerr.
  static const seerrFriend = 'https://seerr.example.net';

  /// A second Prowlarr and a second Dockge on `tower`, and a second Nginx
  /// Proxy Manager on `nas`: in no profile, for a test that adds one beside
  /// the first, two of a service whose Home decisions act on one server.
  static const prowlarrTower = 'http://tower.home.arpa:9696';
  static const dockgeTower = 'http://tower.home.arpa:5001';
  static const npmNas = 'http://nas.home.arpa:81';

  // World B.
  static const readarr = 'http://tower.home.arpa:8787';
  static const emby = 'http://tower.home.arpa:8096';
  static const nzbget = 'http://tower.home.arpa:6789';
  static const unraid = 'https://tower.home.arpa';
  static const npm = 'http://tower.home.arpa:81';
}

/// The arrs as the containers beside them reach them on the household's
/// Docker network: the Compose service name and the port the app listens on
/// inside its container. What Seerr's settings and Prowlarr's applications
/// hold under `ConfigProfile.withDockerHostnames`, and nothing this device
/// can dial.
///
/// Radarr 4K is Radarr's second container: it listens on 7878 inside, like
/// the first, and Docker publishes it on 7879 (behind TLS) outside. So
/// "Seerr's own host with the port Seerr knows" is `nas.home.arpa:7878`,
/// where the first Radarr answers.
abstract final class WorldContainers {
  static const radarr = 'http://radarr:7878';
  static const radarr4k = 'http://radarr-4k:7878';
  static const sonarr = 'http://sonarr:8989';
  static const sonarrAnime = 'http://sonarr-anime:8989';
  static const lidarr = 'http://lidarr:8686';
  static const prowlarr = 'http://prowlarr:9696';

  /// The container address of connection [connectionId], or null for a
  /// connection that is not one of the arrs above.
  static String? of(String connectionId) => switch (connectionId) {
    WorldIds.radarr => radarr,
    WorldIds.radarr4k => radarr4k,
    WorldIds.sonarr => sonarr,
    WorldIds.sonarrAnime => sonarrAnime,
    WorldIds.lidarr => lidarr,
    WorldIds.prowlarr => prowlarr,
    _ => null,
  };
}

/// Connection ids. The first of a service takes the service's own route
/// param, as `ServiceInstance.mintId` hands it out; a second takes
/// `<param>-<7 chars>`, the minted shape.
abstract final class WorldIds {
  static const radarr = 'radarr';
  static const radarr4k = 'radarr-4k00001';
  static const sonarr = 'sonarr';
  static const sonarrAnime = 'sonarr-anime01';
  static const lidarr = 'lidarr';
  static const prowlarr = 'prowlarr';
  static const bazarr = 'bazarr';
  static const qbittorrent = 'qbittorrent';
  static const sabnzbd = 'sabnzbd';
  static const seerr = 'seerr';
  static const jellyfin = 'jellyfin';
  static const dockge = 'dockge';
  static const truenas = 'truenas';
  static const plex = 'plex';
  static const emby = 'emby';
  static const transmission = 'transmission';
  static const jellyfinCabin = 'jellyfin-cabin01';
  static const seerrCabin = 'seerr-cabin001';
  static const plexCabin = 'plex-cabin01';
  static const lidarrVinyl = 'lidarr-vinyl01';
  static const seerrFriend = 'seerr-sara001';
  static const prowlarrTower = 'prowlarr-tower1';
  static const dockgeTower = 'dockge-tower01';
  static const npmNas = 'npm-nas000001';
}

/// The credential a world connection is configured with, and the one the
/// server behind it accepts: Seerr's settings hold the same for each Radarr
/// and Sonarr they know.
String worldKey(String connectionId) => 'world-$connectionId-key';

/// One film or series of the world, with the ids every service agrees on.
class WorldTitle {
  const WorldTitle({
    required this.key,
    required this.title,
    required this.year,
    required this.tmdbId,
    this.imdbId,
    this.tvdbId,
    this.isSeries = false,
  });

  /// Stable handle for a test: `spriteFright`.
  final String key;
  final String title;
  final int year;
  final int tmdbId;
  final String? imdbId;
  final int? tvdbId;
  final bool isSeries;

  String get slug => title.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
}

/// The catalogue. Ids are the world's, not claims about TMDB.
abstract final class WorldTitles {
  static const spriteFright = WorldTitle(
    key: 'spriteFright',
    title: 'Sprite Fright',
    year: 2024,
    tmdbId: 891761,
    imdbId: 'tt14852882',
  );
  static const elephantsDream = WorldTitle(
    key: 'elephantsDream',
    title: 'Elephants Dream',
    year: 2006,
    tmdbId: 9761,
    imdbId: 'tt0807840',
  );
  static const bigBuckBunny = WorldTitle(
    key: 'bigBuckBunny',
    title: 'Big Buck Bunny',
    year: 2008,
    tmdbId: 10378,
    imdbId: 'tt1254207',
  );
  static const sintel = WorldTitle(
    key: 'sintel',
    title: 'Sintel',
    year: 2010,
    tmdbId: 45745,
    imdbId: 'tt1727587',
  );
  static const tearsOfSteel = WorldTitle(
    key: 'tearsOfSteel',
    title: 'Tears of Steel',
    year: 2012,
    tmdbId: 133701,
    imdbId: 'tt2285752',
  );
  static const coffeeRun = WorldTitle(
    key: 'coffeeRun',
    title: 'Coffee Run',
    year: 2020,
    tmdbId: 908389,
  );
  static const spring = WorldTitle(
    key: 'spring',
    title: 'Spring',
    year: 2014,
    tmdbId: 241855,
  );
  static const charge = WorldTitle(
    key: 'charge',
    title: 'Charge',
    year: 2022,
    tmdbId: 1062079,
  );
  static const metropolis = WorldTitle(
    key: 'metropolis',
    title: 'Metropolis',
    year: 1927,
    tmdbId: 19,
    imdbId: 'tt0017136',
  );
  static const cosmosLaundromat = WorldTitle(
    key: 'cosmosLaundromat',
    title: 'Cosmos Laundromat',
    year: 2015,
    tmdbId: 358332,
    tvdbId: 300001,
    isSeries: true,
  );
  static const nightShift = WorldTitle(
    key: 'nightShift',
    title: 'Night Shift',
    year: 2024,
    tmdbId: 300002,
    tvdbId: 300002,
    isSeries: true,
  );
  static const agent327 = WorldTitle(
    key: 'agent327',
    title: 'Agent 327',
    year: 2017,
    tmdbId: 300003,
    tvdbId: 300003,
    isSeries: true,
  );

  static const all = [
    spriteFright,
    elephantsDream,
    bigBuckBunny,
    sintel,
    tearsOfSteel,
    coffeeRun,
    spring,
    charge,
    metropolis,
    cosmosLaundromat,
    nightShift,
    agent327,
  ];

  /// The extended catalogue the testlab materialises: public-domain classics
  /// and well-known films, so a house has a library rather than twelve rows.
  /// The fakes keep [all] for the screens whose counts the UI tests pin; the
  /// exporter and the testlab seed read [catalogue].
  static const catalogueMovies = <WorldTitle>[
    WorldTitle(
      key: 'nosferatu',
      title: 'Nosferatu',
      year: 1922,
      tmdbId: 653,
      imdbId: 'tt0013442',
    ),
    WorldTitle(
      key: 'caligari',
      title: 'The Cabinet of Dr. Caligari',
      year: 1920,
      tmdbId: 234,
      imdbId: 'tt0010323',
    ),
    WorldTitle(
      key: 'theKid',
      title: 'The Kid',
      year: 1921,
      tmdbId: 10098,
      imdbId: 'tt0012349',
    ),
    WorldTitle(
      key: 'casablanca',
      title: 'Casablanca',
      year: 1942,
      tmdbId: 289,
      imdbId: 'tt0034583',
    ),
    WorldTitle(
      key: 'sunsetBoulevard',
      title: 'Sunset Boulevard',
      year: 1950,
      tmdbId: 599,
      imdbId: 'tt0043014',
    ),
    WorldTitle(
      key: 'singinInTheRain',
      title: "Singin' in the Rain",
      year: 1952,
      tmdbId: 872,
      imdbId: 'tt0045152',
    ),
    WorldTitle(
      key: 'rearWindow',
      title: 'Rear Window',
      year: 1954,
      tmdbId: 567,
      imdbId: 'tt0047396',
    ),
    WorldTitle(
      key: 'sevenSamurai',
      title: 'Seven Samurai',
      year: 1954,
      tmdbId: 346,
      imdbId: 'tt0047478',
    ),
    WorldTitle(
      key: 'twelveAngryMen',
      title: '12 Angry Men',
      year: 1957,
      tmdbId: 389,
      imdbId: 'tt0050083',
    ),
    WorldTitle(
      key: 'vertigo',
      title: 'Vertigo',
      year: 1958,
      tmdbId: 426,
      imdbId: 'tt0052357',
    ),
    WorldTitle(
      key: 'northByNorthwest',
      title: 'North by Northwest',
      year: 1959,
      tmdbId: 213,
      imdbId: 'tt0053125',
    ),
    WorldTitle(
      key: 'psycho',
      title: 'Psycho',
      year: 1960,
      tmdbId: 539,
      imdbId: 'tt0054215',
    ),
    WorldTitle(
      key: 'psycho1998',
      title: 'Psycho',
      year: 1998,
      tmdbId: 11252,
      imdbId: 'tt0155975',
    ),
    WorldTitle(
      key: 'breakfastAtTiffanys',
      title: "Breakfast at Tiffany's",
      year: 1961,
      tmdbId: 164,
      imdbId: 'tt0054698',
    ),
    WorldTitle(
      key: 'lawrenceOfArabia',
      title: 'Lawrence of Arabia',
      year: 1962,
      tmdbId: 947,
      imdbId: 'tt0056172',
    ),
    WorldTitle(
      key: 'toKillAMockingbird',
      title: 'To Kill a Mockingbird',
      year: 1962,
      tmdbId: 595,
      imdbId: 'tt0056592',
    ),
    WorldTitle(
      key: 'drStrangelove',
      title: 'Dr. Strangelove',
      year: 1964,
      tmdbId: 935,
      imdbId: 'tt0057012',
    ),
    WorldTitle(
      key: 'theGoodTheBadAndTheUgly',
      title: 'The Good, the Bad and the Ugly',
      year: 1966,
      tmdbId: 429,
      imdbId: 'tt0060196',
    ),
    WorldTitle(
      key: 'twoThousandOne',
      title: '2001: A Space Odyssey',
      year: 1968,
      tmdbId: 62,
      imdbId: 'tt0062622',
    ),
    WorldTitle(
      key: 'theGodfather',
      title: 'The Godfather',
      year: 1972,
      tmdbId: 238,
      imdbId: 'tt0068646',
    ),
    WorldTitle(
      key: 'jaws',
      title: 'Jaws',
      year: 1975,
      tmdbId: 578,
      imdbId: 'tt0073195',
    ),
    WorldTitle(
      key: 'taxiDriver',
      title: 'Taxi Driver',
      year: 1976,
      tmdbId: 103,
      imdbId: 'tt0075314',
    ),
    WorldTitle(
      key: 'starWars',
      title: 'Star Wars',
      year: 1977,
      tmdbId: 11,
      imdbId: 'tt0076759',
    ),
    WorldTitle(
      key: 'alien',
      title: 'Alien',
      year: 1979,
      tmdbId: 348,
      imdbId: 'tt0078748',
    ),
    WorldTitle(
      key: 'bladeRunner',
      title: 'Blade Runner',
      year: 1982,
      tmdbId: 78,
      imdbId: 'tt0083658',
    ),
    WorldTitle(
      key: 'backToTheFuture',
      title: 'Back to the Future',
      year: 1985,
      tmdbId: 105,
      imdbId: 'tt0088763',
    ),
    WorldTitle(
      key: 'dieHard',
      title: 'Die Hard',
      year: 1988,
      tmdbId: 562,
      imdbId: 'tt0095016',
    ),
    WorldTitle(
      key: 'jurassicPark',
      title: 'Jurassic Park',
      year: 1993,
      tmdbId: 329,
      imdbId: 'tt0107290',
    ),
    WorldTitle(
      key: 'shawshank',
      title: 'The Shawshank Redemption',
      year: 1994,
      tmdbId: 278,
      imdbId: 'tt0111161',
    ),
    WorldTitle(
      key: 'pulpFiction',
      title: 'Pulp Fiction',
      year: 1994,
      tmdbId: 680,
      imdbId: 'tt0110912',
    ),
    WorldTitle(
      key: 'fightClub',
      title: 'Fight Club',
      year: 1999,
      tmdbId: 550,
      imdbId: 'tt0137523',
    ),
    WorldTitle(
      key: 'theMatrix',
      title: 'The Matrix',
      year: 1999,
      tmdbId: 603,
      imdbId: 'tt0133093',
    ),
  ];

  /// The series the testlab materialises: finished shows, ongoing shows and
  /// three anime, so the calendars and the Sonarr hierarchy have real shapes.
  static const catalogueSeries = <WorldTitle>[
    WorldTitle(
      key: 'breakingBad',
      title: 'Breaking Bad',
      year: 2008,
      tmdbId: 1396,
      tvdbId: 81189,
      isSeries: true,
    ),
    WorldTitle(
      key: 'theOffice',
      title: 'The Office',
      year: 2005,
      tmdbId: 2316,
      tvdbId: 73244,
      isSeries: true,
    ),
    WorldTitle(
      key: 'parksAndRec',
      title: 'Parks and Recreation',
      year: 2009,
      tmdbId: 8592,
      tvdbId: 84912,
      isSeries: true,
    ),
    WorldTitle(
      key: 'brooklynNineNine',
      title: 'Brooklyn Nine-Nine',
      year: 2013,
      tmdbId: 48891,
      tvdbId: 261661,
      isSeries: true,
    ),
    WorldTitle(
      key: 'theExpanse',
      title: 'The Expanse',
      year: 2015,
      tmdbId: 63639,
      tvdbId: 280619,
      isSeries: true,
    ),
    WorldTitle(
      key: 'arcane',
      title: 'Arcane',
      year: 2021,
      tmdbId: 94605,
      tvdbId: 371028,
      isSeries: true,
    ),
    WorldTitle(
      key: 'severance',
      title: 'Severance',
      year: 2022,
      tmdbId: 95396,
      tvdbId: 371980,
      isSeries: true,
    ),
    WorldTitle(
      key: 'bluey',
      title: 'Bluey',
      year: 2018,
      tmdbId: 82728,
      tvdbId: 348545,
      isSeries: true,
    ),
    WorldTitle(
      key: 'avatar',
      title: 'Avatar: The Last Airbender',
      year: 2005,
      tmdbId: 246,
      tvdbId: 74880,
      isSeries: true,
    ),
  ];

  static const catalogue = [...all, ...catalogueMovies, ...catalogueSeries];

  static WorldTitle byKey(String key) =>
      catalogue.firstWhere((t) => t.key == key);
}

/// One recording artist and its albums, with the ids Lidarr and MusicBrainz
/// agree on.
class WorldArtist {
  const WorldArtist({
    required this.key,
    required this.name,
    required this.foreignArtistId,
    required this.albums,
  });

  final String key;
  final String name;
  final String foreignArtistId;
  final List<WorldAlbum> albums;
}

class WorldAlbum {
  const WorldAlbum({
    required this.title,
    required this.year,
    required this.foreignAlbumId,
    required this.tracks,
  });

  final String title;
  final int year;
  final String foreignAlbumId;
  final int tracks;
}

/// The music the testlab materialises: eight artists, one album each, so
/// Lidarr's shelves and the artist page have something to draw.
abstract final class WorldMusic {
  static const all = <WorldArtist>[
    WorldArtist(
      key: 'daftPunk',
      name: 'Daft Punk',
      foreignArtistId: '056e4f3e-d505-4dad-8ec1-d04f521cbb56',
      albums: [
        WorldAlbum(
          title: 'Discovery',
          year: 2001,
          foreignAlbumId: 'album-daft-punk-discovery',
          tracks: 14,
        ),
      ],
    ),
    WorldArtist(
      key: 'massiveAttack',
      name: 'Massive Attack',
      foreignArtistId: 'artist-massive-attack',
      albums: [
        WorldAlbum(
          title: 'Mezzanine',
          year: 1998,
          foreignAlbumId: 'album-massive-attack-mezzanine',
          tracks: 11,
        ),
      ],
    ),
    WorldArtist(
      key: 'boardsOfCanada',
      name: 'Boards of Canada',
      foreignArtistId: 'artist-boards-of-canada',
      albums: [
        WorldAlbum(
          title: 'Music Has the Right to Children',
          year: 1998,
          foreignAlbumId: 'album-boc-mhtrtc',
          tracks: 18,
        ),
      ],
    ),
    WorldArtist(
      key: 'aphexTwin',
      name: 'Aphex Twin',
      foreignArtistId: 'artist-aphex-twin',
      albums: [
        WorldAlbum(
          title: 'Selected Ambient Works 85-92',
          year: 1992,
          foreignAlbumId: 'album-aphex-saw',
          tracks: 13,
        ),
      ],
    ),
    WorldArtist(
      key: 'bonobo',
      name: 'Bonobo',
      foreignArtistId: 'artist-bonobo',
      albums: [
        WorldAlbum(
          title: 'Black Sands',
          year: 2010,
          foreignAlbumId: 'album-bonobo-black-sands',
          tracks: 12,
        ),
      ],
    ),
    WorldArtist(
      key: 'air',
      name: 'Air',
      foreignArtistId: 'artist-air',
      albums: [
        WorldAlbum(
          title: 'Moon Safari',
          year: 1998,
          foreignAlbumId: 'album-air-moon-safari',
          tracks: 10,
        ),
      ],
    ),
    WorldArtist(
      key: 'portishead',
      name: 'Portishead',
      foreignArtistId: 'artist-portishead',
      albums: [
        WorldAlbum(
          title: 'Dummy',
          year: 1994,
          foreignAlbumId: 'album-portishead-dummy',
          tracks: 11,
        ),
      ],
    ),
    WorldArtist(
      key: 'cinematicOrchestra',
      name: 'The Cinematic Orchestra',
      foreignArtistId: 'artist-cinematic-orchestra',
      albums: [
        WorldAlbum(
          title: 'Ma Fleur',
          year: 2007,
          foreignAlbumId: 'album-cinematic-ma-fleur',
          tracks: 11,
        ),
      ],
    ),
  ];
}

/// One author and its books, for Readarr's shelves.
class WorldAuthor {
  const WorldAuthor({
    required this.key,
    required this.name,
    required this.foreignAuthorId,
    required this.books,
  });

  final String key;
  final String name;
  final String foreignAuthorId;
  final List<WorldBook> books;
}

class WorldBook {
  const WorldBook({
    required this.title,
    required this.year,
    required this.foreignBookId,
  });

  final String title;
  final int year;
  final String foreignBookId;
}

abstract final class WorldBooks {
  static const all = <WorldAuthor>[
    WorldAuthor(
      key: 'verne',
      name: 'Jules Verne',
      foreignAuthorId: 'author-jules-verne',
      books: [
        WorldBook(
          title: 'Twenty Thousand Leagues Under the Seas',
          year: 1870,
          foreignBookId: 'book-verne-20000',
        ),
      ],
    ),
    WorldAuthor(
      key: 'wells',
      name: 'H. G. Wells',
      foreignAuthorId: 'author-hg-wells',
      books: [
        WorldBook(
          title: 'The War of the Worlds',
          year: 1898,
          foreignBookId: 'book-wells-war',
        ),
      ],
    ),
    WorldAuthor(
      key: 'shelley',
      name: 'Mary Shelley',
      foreignAuthorId: 'author-mary-shelley',
      books: [
        WorldBook(
          title: 'Frankenstein',
          year: 1818,
          foreignBookId: 'book-shelley-frankenstein',
        ),
      ],
    ),
    WorldAuthor(
      key: 'stoker',
      name: 'Bram Stoker',
      foreignAuthorId: 'author-bram-stoker',
      books: [
        WorldBook(
          title: 'Dracula',
          year: 1897,
          foreignBookId: 'book-stoker-dracula',
        ),
      ],
    ),
    WorldAuthor(
      key: 'doyle',
      name: 'Arthur Conan Doyle',
      foreignAuthorId: 'author-conan-doyle',
      books: [
        WorldBook(
          title: 'The Hound of the Baskervilles',
          year: 1902,
          foreignBookId: 'book-doyle-hound',
        ),
      ],
    ),
    WorldAuthor(
      key: 'austen',
      name: 'Jane Austen',
      foreignAuthorId: 'author-jane-austen',
      books: [
        WorldBook(
          title: 'Pride and Prejudice',
          year: 1813,
          foreignBookId: 'book-austen-pride',
        ),
      ],
    ),
  ];
}

/// The people on the Seerr side.
abstract final class WorldPeople {
  /// The operator. Seerr user 1, admin.
  static const operatorName = 'Matt';
  static const anna = 'Anna';
  static const luca = 'Luca';

  /// The friend whose Seerr the operator requests from (P9).
  static const friend = 'Sara';
}

/// Where a download is in its life.
enum DownloadState {
  downloading,
  stuck,
  queued,
  importBlocked,
  seeding,
  stopped,

  /// The client cannot read or write the data: qBittorrent's `error`,
  /// Transmission's local error. None of the world's own downloads is in this
  /// state; a test adds one with `ConfigProfile.withDownloads`.
  failed,

  /// The data is not where the client left it: qBittorrent's `missingFiles`,
  /// Transmission's local error. Added the same way as [failed].
  missingFiles,

  /// The client paused the job itself and waits on a person: a SABnzbd slot
  /// `Paused` with an `ENCRYPTED` label, an NZBGet group paused by its health
  /// check. The arr's queue calls it paused. Added the same way as [failed].
  heldByClient,

  /// Somebody paused the download, with bytes still to come: qBittorrent's
  /// `stoppedDL`, a stopped Transmission torrent, a SABnzbd slot `Paused`
  /// with no label, an NZBGet group `PAUSED`. The arr's queue calls it
  /// paused. Added the same way as [failed].
  paused,
}

/// One download of the world, as both the arr's queue and the client see it.
///
/// [id] is the join: a qBittorrent hash (lower-case in qB, upper-case in the
/// arr's `downloadId`), a SABnzbd `nzo_id`, a Transmission `hashString`.
class WorldDownload {
  const WorldDownload({
    required this.id,
    required this.release,
    required this.client,
    required this.state,
    required this.progress,
    required this.size,
    this.arr,
    this.title,
    this.season,
    this.episode,
    this.speed = 0,
    this.eta,
    this.onlyWithClient = false,
    this.peers,
  });

  final String id;
  final String release;

  /// `qbittorrent`, `sabnzbd` or `transmission`, a `ServiceKey` name.
  final String client;
  final DownloadState state;

  /// 0…1.
  final double progress;
  final int size;

  /// The arr connection whose queue carries this row (a [WorldIds] value), or
  /// null for a torrent nobody's arr grabbed.
  final String? arr;
  final WorldTitle? title;
  final int? season;
  final int? episode;

  /// Bytes per second.
  final int speed;
  final Duration? eta;

  /// Present only in a profile that configures [client]: the Transmission row
  /// P4 needs would otherwise sit in P1's Sonarr queue, where the brief has
  /// exactly five downloads in flight.
  final bool onlyWithClient;

  /// How many peers are sending it (Transmission's `peersSendingToUs`,
  /// qBittorrent's `num_seeds`), or null for the fakes' own default.
  final int? peers;

  int get sizeLeft => (size * (1 - progress)).round();

  /// A copy where what changed changed: the world's life
  /// (`world_life.dart`) moves a download on, pauses it, hands it over.
  /// [clearArr] lets go of the arr, for a row its queue no longer carries.
  WorldDownload copyWith({
    DownloadState? state,
    double? progress,
    int? speed,
    Duration? eta,
    bool clearEta = false,
    bool clearArr = false,
  }) => WorldDownload(
    id: id,
    release: release,
    client: client,
    state: state ?? this.state,
    progress: progress ?? this.progress,
    size: size,
    arr: clearArr ? null : arr,
    title: title,
    season: season,
    episode: episode,
    speed: speed ?? this.speed,
    eta: clearEta ? null : (eta ?? this.eta),
    onlyWithClient: onlyWithClient,
    peers: peers,
  );
}

abstract final class WorldDownloads {
  static const _mb = 1024 * 1024;
  static const _gb = 1024 * 1024 * 1024;

  static const spriteFright = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345601',
    release: 'Sprite.Fright.2021.1080p.WEB',
    client: 'qbittorrent',
    state: DownloadState.downloading,
    progress: 0.62,
    size: 2 * _gb,
    arr: WorldIds.radarr,
    title: WorldTitles.spriteFright,
    speed: (4.2 * _mb) ~/ 1,
    eta: Duration(minutes: 11),
  );

  static const bigBuckBunny = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345602',
    release: 'Big.Buck.Bunny.2008.1080p.BluRay',
    client: 'qbittorrent',
    state: DownloadState.stuck,
    progress: 0.47,
    size: (2.34 * _gb) ~/ 1,
    arr: WorldIds.radarr,
    title: WorldTitles.bigBuckBunny,
  );

  static const cosmosS02E04 = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345603',
    release: 'Cosmos.Laundromat.S02E04.1080p.WEB',
    client: 'qbittorrent',
    state: DownloadState.downloading,
    progress: 0.88,
    size: (1.2 * _gb) ~/ 1,
    arr: WorldIds.sonarr,
    title: WorldTitles.cosmosLaundromat,
    season: 2,
    episode: 4,
    speed: (12.1 * _mb) ~/ 1,
    eta: Duration(minutes: 1),
  );

  static const cosmosS02E05 = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345604',
    release: 'Cosmos.Laundromat.S02E05.1080p.WEB',
    client: 'qbittorrent',
    state: DownloadState.downloading,
    progress: 0.09,
    size: (1.2 * _gb) ~/ 1,
    arr: WorldIds.sonarr,
    title: WorldTitles.cosmosLaundromat,
    season: 2,
    episode: 5,
    speed: (6.1 * _mb) ~/ 1,
    eta: Duration(minutes: 24),
  );

  static const elephantsDream4k = WorldDownload(
    id: 'SABnzbd_nzo_elephants4k',
    release: 'Elephants.Dream.2006.2160p.UHD.BluRay',
    client: 'sabnzbd',
    state: DownloadState.downloading,
    progress: 0.31,
    size: (9.4 * _gb) ~/ 1,
    arr: WorldIds.radarr4k,
    title: WorldTitles.elephantsDream,
    speed: 18 * _mb,
    eta: Duration(minutes: 6),
  );

  static const sintel4k = WorldDownload(
    id: 'SABnzbd_nzo_sintel4k',
    release: 'Sintel.2010.2160p.UHD.BluRay',
    client: 'sabnzbd',
    state: DownloadState.queued,
    progress: 0,
    size: (8.1 * _gb) ~/ 1,
    arr: WorldIds.radarr4k,
    title: WorldTitles.sintel,
    eta: Duration(minutes: 6),
  );

  static const sintelSeeding = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345605',
    release: 'Sintel.2010.1080p.BluRay',
    client: 'qbittorrent',
    state: DownloadState.seeding,
    progress: 1,
    size: (2.2 * _gb) ~/ 1,
  );

  static const tearsOfSteelSeeding = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345606',
    release: 'Tears.of.Steel.2012.1080p',
    client: 'qbittorrent',
    state: DownloadState.seeding,
    progress: 1,
    size: (1.9 * _gb) ~/ 1,
  );

  static const ubuntu = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345607',
    release: 'ubuntu-24.04.1-desktop-amd64.iso',
    client: 'qbittorrent',
    state: DownloadState.stopped,
    progress: 1,
    size: (5.7 * _gb) ~/ 1,
  );

  /// P4's second client: one Sonarr grab through Transmission.
  static const nightShiftTransmission = WorldDownload(
    id: 'b2e1d4c5f6a70819304b5c6d7e8f901234567801',
    release: 'Night.Shift.S02E04.1080p.WEB',
    client: 'transmission',
    state: DownloadState.downloading,
    progress: 0.4,
    size: (1.1 * _gb) ~/ 1,
    arr: WorldIds.sonarr,
    title: WorldTitles.nightShift,
    season: 2,
    episode: 4,
    speed: 3 * _mb,
    eta: Duration(minutes: 4),
    onlyWithClient: true,
  );

  /// The 18 finished Sonarr grabs that need a manual import: 12 WEB upgrades
  /// whose names say their episode, 6 tapes whose names do not.
  static final List<WorldDownload> blockedImports = [
    for (final (i, (season, episode)) in const [
      (1, 1),
      (1, 2),
      (1, 3),
      (1, 4),
      (1, 5),
      (1, 6),
      (1, 7),
      (1, 8),
      (1, 9),
      (1, 10),
      (2, 1),
      (2, 2),
    ].indexed)
      WorldDownload(
        id: 'c3f2e5d6a7b8091a2b3c4d5e6f70819203${(40 + i).toString().padLeft(6, '0')}',
        release:
            'Kosmische.Wasserette.S${_two(season)}E${_two(episode)}.1080p.WEB',
        client: 'qbittorrent',
        state: DownloadState.importBlocked,
        progress: 1,
        size: (1.1 * _gb) ~/ 1,
        arr: WorldIds.sonarr,
        title: WorldTitles.cosmosLaundromat,
        season: season,
        episode: episode,
      ),
    for (var tape = 1; tape <= 6; tape++)
      WorldDownload(
        id: 'c3f2e5d6a7b8091a2b3c4d5e6f70819203${(60 + tape).toString().padLeft(6, '0')}',
        release: 'Laundromat.Tapes.E${_two(tape)}.720p.WEB',
        client: 'qbittorrent',
        state: DownloadState.importBlocked,
        progress: 1,
        size: (0.7 * _gb) ~/ 1,
        arr: WorldIds.sonarr,
        title: WorldTitles.cosmosLaundromat,
      ),
  ];

  static final List<WorldDownload> all = [
    spriteFright,
    bigBuckBunny,
    cosmosS02E04,
    cosmosS02E05,
    elephantsDream4k,
    sintel4k,
    sintelSeeding,
    tearsOfSteelSeeding,
    ubuntu,
    nightShiftTransmission,
    ...blockedImports,
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// The raw message Sonarr attaches to every blocked import.
  static const blockedImportMessage =
      'Found matching series via grab history, but release was matched to '
      'series by ID. Automatic import is not possible. See the FAQ for '
      'details.';
}
