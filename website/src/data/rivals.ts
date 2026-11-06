// Other apps people search for, described only by what their own website and
// store listing say, with the sources and the day they were read. When a fact
// is not on those pages it is left out rather than guessed. Re-check every
// row before changing `checked`.

export interface Fact {
  label: string;
  them: string;
  cupola: string;
}

export interface Rival {
  id: string;
  name: string;
  /** The <title>. */
  title: string;
  /** What the page answers, as its H1. */
  heading: string;
  description: string;
  /** The answer, first sentence of the page. */
  lede: string;
  checked: string;
  facts: Fact[];
  /** Where the other app is ahead, said plainly. */
  ahead: string[];
  /** Where Cupola stands out, said first. */
  differs: string[];
  moving: string[];
  sources: { label: string; url: string }[];
}

const cupola = {
  platforms: 'iPhone, iPad, Android and Mac; Windows and Linux builds not yet tested on real machines',
  price: 'Free, nothing to unlock',
  source: 'Open source, Apache License 2.0',
  account: 'None. Your services keep their own sign-in',
};

export const rivals: Rival[] = [
  {
    id: 'nzb360',
    name: 'nzb360',
    title: 'An nzb360 alternative for iPhone, Android and Mac · Cupola',
    heading: 'Looking for nzb360 on iPhone?',
    description:
      'nzb360 is Android only, with a paid Pro upgrade. Cupola is free and open source, on iPhone, iPad, Mac and Android.',
    lede: 'nzb360 is Android only. Cupola does much of the same on iPhone, iPad and Mac as well as Android, and it is free and open source.',
    checked: '25 October 2026',
    facts: [
      { label: 'Platforms', them: 'Android', cupola: cupola.platforms },
      { label: 'Price', them: 'Free to install, with a paid Pro upgrade', cupola: cupola.price },
      { label: 'Source code', them: 'No public source found', cupola: cupola.source },
      { label: 'Around since', them: '2012', cupola: '2026 as Cupola, earlier as Seekarr' },
      {
        label: 'Download clients',
        them: 'SABnzbd, NZBGet, qBittorrent, Transmission, Deluge, µTorrent, rTorrent',
        cupola: 'SABnzbd, NZBGet, qBittorrent, Transmission',
      },
      {
        label: 'Media and requests',
        them: 'Sonarr, Radarr, Lidarr, Bazarr, Seerr, Chaptarr, Sick Beard',
        cupola: 'Sonarr, Radarr, Lidarr, Readarr, Bazarr, Seerr (with sign-in for household members)',
      },
      { label: 'Indexers', them: 'Prowlarr, NZBHydra2, Jackett, Newznab', cupola: 'Prowlarr' },
      {
        label: 'Server and streaming',
        them: 'Unraid, Docker containers, Tautulli, Tracearr',
        cupola: 'Unraid, TrueNAS, Dockge, Nginx Proxy Manager, Jellyfin, Plex and Emby sessions, Tracearr',
      },
    ],
    ahead: [
      'Around since 2012, with more than 800,000 downloads on Google Play.',
      'More download clients and indexers: Deluge, µTorrent, rTorrent, NZBHydra2, Jackett and Newznab.',
      'Wake-on-LAN and Tautulli.',
    ],
    differs: [
      'On iPhone, iPad and Mac, as well as Android.',
      'Free and open source, with nothing to unlock.',
      'Reaches the server underneath: TrueNAS, Dockge and Nginx Proxy Manager.',
      'Family members can request with their own Seerr account.',
    ],
    moving: [
      'Cupola does not import nzb360 settings: add each connection again with the same address and key.',
      'Test each connection before you save it. If it fails, Cupola tells you why.',
    ],
    sources: [
      { label: 'nzb360 website', url: 'https://nzb360.com/' },
      { label: 'nzb360 on Google Play', url: 'https://play.google.com/store/apps/details?id=com.kevinforeman.nzb360' },
    ],
  },
  {
    id: 'helmarr',
    name: 'Helmarr',
    title: 'A free Helmarr alternative, also on Android · Cupola',
    heading: 'Comparing Helmarr and Cupola.',
    description:
      'Helmarr is Apple-only, with paid tiers and iOS 26 or later. Cupola is free and open source, on iPhone, Android and Mac from iOS 17.',
    lede: 'Helmarr runs only on Apple devices, needs iOS 26, and charges for its Pro and Ultra tiers. Cupola is free and open source, runs on Android too, and works back to iOS 17.',
    checked: '25 October 2026',
    facts: [
      { label: 'Platforms', them: 'iPhone, iPad, Mac (Apple silicon) and Vision Pro', cupola: cupola.platforms },
      { label: 'Oldest system', them: 'iOS 26', cupola: 'iOS 17, Android 7, macOS 12 (Apple silicon)' },
      {
        label: 'Price',
        them: 'Free to install. Pro at $3.99 a month or $34.99 once, Ultra at $4.99 a month, or single services from $3.99',
        cupola: cupola.price,
      },
      { label: 'Source code', them: 'No public source found', cupola: cupola.source },
      {
        label: 'Data collected by the app',
        them: 'Usage data for analytics and crash data, not linked to you (App Store privacy label)',
        cupola: 'None on iPhone, iPad and Mac. On Android, the code scanner (Google ML Kit) sends Google diagnostic and usage data; we collect nothing ourselves',
      },
      {
        label: 'Media and requests',
        them: 'Sonarr, Radarr, Lidarr, Bazarr, Seerr, Overseerr, Jellyseerr, Wizarr',
        cupola: 'Sonarr, Radarr, Lidarr, Readarr, Bazarr, Seerr (with sign-in for household members)',
      },
      {
        label: 'Download clients and indexers',
        them: 'SABnzbd, NZBGet, qBittorrent, Transmission, Deluge, rTorrent, Prowlarr, NZBHydra2, Jackett',
        cupola: 'SABnzbd, NZBGet, qBittorrent, Transmission, Prowlarr',
      },
      {
        label: 'Streaming and server',
        them: 'Plex, Emby, Tautulli, Jellystat, Tracearr, Tdarr, Unraid, SSH',
        cupola: 'Jellyfin, Plex, Emby, Tracearr, Unraid, TrueNAS, Dockge, Nginx Proxy Manager',
      },
    ],
    ahead: [
      'More services in places: Tdarr, Deluge, rTorrent, NZBHydra2, Jackett, Tautulli, Jellystat and Wizarr.',
      'An SSH and SFTP client, and a Vision Pro app.',
      'A large App Store following, rated 4.8.',
    ],
    differs: [
      'On Android as well as iPhone, iPad and Mac, and on iOS 17 or later.',
      'Free and open source: no subscription, no per-service unlocks.',
      'On iPhone, iPad and Mac, collects nothing, not even anonymous analytics.',
      'Reaches TrueNAS, Dockge and Nginx Proxy Manager, and family members can request with their own Seerr account.',
    ],
    moving: [
      'Cupola does not import Helmarr settings: add each connection again with the same address and key, plus an away address if you use one.',
      'Test each connection before you save it. If it fails, Cupola tells you why.',
    ],
    sources: [
      { label: 'Helmarr website', url: 'https://helmarr.com/' },
      { label: 'Helmarr on the App Store', url: 'https://apps.apple.com/app/id1638624921' },
    ],
  },
  {
    id: 'lunasea',
    name: 'LunaSea',
    title: 'A LunaSea alternative for Radarr, Sonarr and more · Cupola',
    heading: 'Coming from LunaSea.',
    description:
      'LunaSea published its final release and was archived. Cupola covers the same services and more, and it is free, open source and still developed.',
    lede: 'LunaSea is no longer developed: it published a final release and was archived. Cupola does the same job for Radarr, Sonarr and the download clients, goes further, and keeps improving.',
    checked: '25 October 2026',
    facts: [
      { label: 'Status', them: 'Final release, v11.0.0, on 3 April 2025; repository archived', cupola: 'Actively developed' },
      { label: 'Source code', them: 'On GitHub, archived', cupola: cupola.source },
      { label: 'Platforms', them: 'No longer updated for new system versions', cupola: cupola.platforms },
    ],
    ahead: [],
    differs: [
      'Actively developed, on iPhone, iPad, Android and Mac.',
      'Goes further: Seerr, Prowlarr, Bazarr, Jellyfin, Plex, Emby and the server underneath.',
      'Built around what needs you: Home shows what arrived and what is stuck, and every fault comes with its fix.',
      'Each service still has its own screens when you want the details.',
    ],
    moving: [
      'Cupola cannot read LunaSea\'s settings or backups: set each connection up again with the same address and key.',
      'There is no Tautulli or Wake-on-LAN. Cupola reads sessions from Jellyfin, Plex and Emby directly.',
    ],
    sources: [{ label: 'LunaSea releases on GitHub', url: 'https://github.com/JagandeepBrar/LunaSea/releases' }],
  },
  {
    id: 'ruddarr',
    name: 'Ruddarr',
    title: 'A Ruddarr alternative, also on Android · Cupola',
    heading: 'Comparing Ruddarr and Cupola.',
    description:
      'Ruddarr covers Radarr and Sonarr on iOS 26. Cupola covers nineteen services, runs on Android and iOS 17, and is free with no subscription.',
    lede: 'Ruddarr is a polished, open-source app for Radarr and Sonarr on iPhone and iPad, from iOS 26. Cupola covers seventeen more services, runs on Android and older iPhones, and is free with nothing to subscribe to.',
    checked: '30 October 2026',
    facts: [
      {
        label: 'Platforms',
        them: 'iPhone and iPad; on Apple silicon Macs as an iPad app, which the App Store lists as not verified for macOS',
        cupola: cupola.platforms,
      },
      { label: 'Oldest system', them: 'iOS 26', cupola: 'iOS 17, Android 7, macOS 12 (Apple silicon)' },
      { label: 'Price', them: 'Free. Notifications need Ruddarr+, a $5.99 in-app subscription', cupola: cupola.price },
      { label: 'Source code', them: 'Open source, MIT License', cupola: cupola.source },
      { label: 'Around since', them: '2024 (first release in April)', cupola: '2026 as Cupola, earlier as Seekarr' },
      {
        label: 'Services',
        them: 'Radarr and Sonarr',
        cupola: 'Nineteen: Radarr, Sonarr, Lidarr, Readarr, Bazarr, Seerr, Prowlarr, four download clients, Jellyfin, Plex, Emby, Tracearr and the server underneath',
      },
      { label: 'Languages', them: 'English and seven more', cupola: 'English only' },
    ],
    ahead: [
      'Fine-grained push notifications (with Ruddarr+), Siri Shortcuts, Spotlight and iCloud sync.',
      'Translated into eight languages; Cupola is English only.',
      'A long App Store record: 4.9 out of 5 from 767 ratings when we checked.',
    ],
    differs: [
      'Nineteen services instead of two: Seerr, Lidarr, Bazarr, Prowlarr, download clients, Jellyfin, Plex, Emby, Tracearr and your server.',
      'On Android too, and on iPhones back to iOS 17.',
      'Notifications are free: your phone checks your services itself.',
      'Family members can request with their own Seerr account.',
    ],
    moving: [
      'Cupola does not import Ruddarr settings: add Radarr and Sonarr again with the same address and key.',
      'Custom headers for your reverse proxy go in each connection\'s access settings.',
      'Test each connection before you save it. If it fails, Cupola tells you why.',
    ],
    sources: [
      { label: 'Ruddarr on GitHub', url: 'https://github.com/ruddarr/app' },
      { label: 'Ruddarr on the App Store', url: 'https://apps.apple.com/app/ruddarr/id6476240130' },
    ],
  },
  {
    id: 'arrmatey',
    name: 'ArrMatey',
    title: 'An ArrMatey alternative for iPhone, Android and Mac · Cupola',
    heading: 'Comparing ArrMatey and Cupola.',
    description:
      'ArrMatey ships as an Android APK, and its iOS app is built from source. Cupola installs on iPhone, iPad, Mac and Android today, free and open source.',
    lede: 'ArrMatey is an open-source arr client for Android; on iOS you build it yourself in Xcode. Cupola installs on iPhone, iPad and Mac from a public beta and on Android from an APK, and reaches further into downloads, streaming and your server.',
    checked: '30 October 2026',
    facts: [
      { label: 'Platforms', them: 'Android; iOS when built from source', cupola: cupola.platforms },
      { label: 'Price', them: 'No price stated; donation links', cupola: cupola.price },
      { label: 'Source code', them: 'Open source, MIT License', cupola: cupola.source },
      { label: 'Around since', them: '2026 (first release in February), still before 1.0', cupola: '2026 as Cupola, earlier as Seekarr' },
      {
        label: 'Media and requests',
        them: 'Sonarr, Radarr, Lidarr, Bookshelf, Listenarr, Seerr, Bazarr',
        cupola: 'Sonarr, Radarr, Lidarr, Readarr, Bazarr, Seerr (with sign-in for household members)',
      },
      {
        label: 'Download clients and indexers',
        them: 'qBittorrent, Transmission, Deluge, SABnzbd, Prowlarr',
        cupola: 'SABnzbd, NZBGet, qBittorrent, Transmission, Prowlarr',
      },
      {
        label: 'Streaming and server',
        them: 'Tracearr',
        cupola: 'Jellyfin, Plex and Emby sessions, Tracearr, TrueNAS, Unraid, Dockge, Nginx Proxy Manager',
      },
    ],
    ahead: [
      'Book and audiobook apps, Bookshelf and Listenarr, plus Deluge.',
      'A dashboard you arrange yourself, and import and export of settings.',
    ],
    differs: [
      'Installs on iPhone, iPad and Mac from a public TestFlight beta, no Xcode needed.',
      'Reaches your server: TrueNAS, Unraid, Dockge and Nginx Proxy Manager.',
      'Jellyfin, Plex and Emby sessions, and NZBGet.',
      'Family members can request with their own Seerr account.',
    ],
    moving: [
      'Cupola does not import ArrMatey settings: add each connection again with the same address and key or password.',
      'Test each connection before you save it. If it fails, Cupola tells you why.',
    ],
    sources: [
      { label: 'ArrMatey on GitHub', url: 'https://github.com/owenlejeune/arrmatey' },
      { label: 'ArrMatey releases', url: 'https://github.com/owenlejeune/arrmatey/releases' },
    ],
  },
];
