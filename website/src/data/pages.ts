// Every page's name, words for search and social cards, and the title that
// lights its card. The OG images, the sitemap order in llms.txt and the
// related links all read from here.
import type { LightId } from './titles';
import { rivals } from './rivals';
import { services, type Category } from '../lib/repo';

export interface Page {
  path: string;
  slug: string;
  /** Short name, for links and breadcrumbs. */
  name: string;
  /** The <title>. */
  title: string;
  /** What the page answers, shown on its social card. */
  heading: string;
  description: string;
  light: LightId;
}

export const pages = {
  home: {
    path: '/',
    slug: 'home',
    name: 'Cupola',
    title: 'Cupola: Radarr, Sonarr and Seerr app for iPhone and Android',
    heading: 'A Cupola over your server.',
    description: 'A free, open-source app for Radarr, Sonarr, Seerr, qBittorrent and the rest of your self-hosted media stack. iPhone, Android and Mac. No account, no cloud.',
    light: 'singularity',
  },
  services: {
    path: '/services/',
    slug: 'services',
    name: 'Services',
    title: 'Cupola services: Radarr, Sonarr, Seerr, qBittorrent, TrueNAS',
    heading: 'Nineteen services, tested honestly.',
    description: 'Every service Cupola connects to, what it can do with each, how it signs in, and whether it has been verified against a real, running instance.',
    light: 'lamp',
  },
  install: {
    path: '/install/',
    slug: 'install',
    name: 'Install',
    title: 'Install Cupola on iPhone, Android, Mac, Windows and Linux',
    heading: 'Get Cupola on every device you use.',
    description: 'How to install Cupola: the TestFlight beta on iPhone, iPad and Mac, the APK on Android, the dmg, Windows and Linux builds, building from source, and what you need first.',
    light: 'spring',
  },
  privacy: {
    path: '/privacy/',
    slug: 'privacy',
    name: 'Privacy',
    title: 'Privacy and security · Cupola',
    heading: 'Your data stays with you.',
    description: 'Cupola talks straight to your own services. How it stores keys, pins self-signed certificates, which other hosts it contacts, and what reaches Google on Android.',
    light: 'lamp',
  },
  faq: {
    path: '/faq/',
    slug: 'faq',
    name: 'FAQ',
    title: 'Questions about Cupola, answered',
    heading: 'Questions, answered plainly.',
    description: 'Does Cupola need an account? Does it work away from home, with Overseerr and Jellyseerr, with self-signed certificates? Is it free? The answers, in one place.',
    light: 'lamp',
  },
  arr: {
    path: '/radarr-sonarr-app/',
    slug: 'radarr-sonarr-app',
    name: 'Radarr and Sonarr',
    title: 'Radarr and Sonarr app for iPhone and Android · Cupola',
    heading: 'Radarr, Sonarr and Lidarr, on your phone.',
    description: 'A free, native Radarr, Sonarr, Lidarr and Readarr app for iPhone, Android and Mac: libraries, calendar, queue, interactive search and manual import.',
    light: 'tos',
  },
  seerr: {
    path: '/seerr-requests/',
    slug: 'seerr-requests',
    name: 'Requests with Seerr',
    title: 'Overseerr and Jellyseerr app for iPhone and Android · Cupola',
    heading: 'Requests for everyone at home.',
    description: 'Seerr, Overseerr and Jellyseerr as a native app: Discover, requests and approvals for the admin, and a simpler app for everyone else at home.',
    light: 'sintel',
  },
  downloads: {
    path: '/download-clients/',
    slug: 'download-clients',
    name: 'Download clients',
    title: 'qBittorrent, SABnzbd and NZBGet from your phone · Cupola',
    heading: 'Every download in one list.',
    description: 'qBittorrent, Transmission, SABnzbd, NZBGet and Prowlarr from iPhone or Android: one live queue, stuck downloads explained, speed limits and indexers.',
    light: 'charge',
  },
  stream: {
    path: '/jellyfin-plex/',
    slug: 'jellyfin-plex',
    name: 'Jellyfin and Plex',
    title: 'Jellyfin and Plex sessions from your phone · Cupola',
    heading: 'Who is watching, and why it is transcoding.',
    description: 'See who is watching on Jellyfin and Plex, why a stream transcodes, and pause, stop or message a session from your phone. Libraries, devices and tasks too.',
    light: 'sintel',
  },
  homelab: {
    path: '/homelab/',
    slug: 'homelab',
    name: 'NAS and homelab',
    title: 'TrueNAS, Unraid and Dockge from your phone · Cupola',
    heading: 'Your server, in the same app.',
    description: 'TrueNAS pools and apps, Unraid arrays and VMs, Dockge stacks with a live terminal, Nginx Proxy Manager hosts: the box under your media apps, in Cupola.',
    light: 'lamp',
  },
  alternatives: {
    path: '/alternatives/',
    slug: 'alternatives',
    name: 'Alternatives',
    title: 'Cupola compared with nzb360, LunaSea, Ruddarr and more',
    heading: 'Cupola and the other apps.',
    description: 'How Cupola compares with nzb360, Helmarr, LunaSea, Ruddarr and ArrMatey: platforms, price, source code and services, from each app\'s own pages.',
    light: 'lamp',
  },
  contribute: {
    path: '/contribute/',
    slug: 'contribute',
    name: 'Contribute',
    title: 'Contribute to Cupola',
    heading: 'Help make it work on your stack too.',
    description: 'Cupola is open source. The most useful help is a report from a service you run; then accessibility, integrations and code. Here is how.',
    light: 'lamp',
  },
  press: {
    path: '/press/',
    slug: 'press',
    name: 'Press kit',
    title: 'Press kit · Cupola',
    heading: 'Writing about Cupola?',
    description: 'Cupola described in a line and in a paragraph, the mark, the tagline, and the facts worth checking.',
    light: 'lamp',
  },
  credits: {
    path: '/credits/',
    slug: 'credits',
    name: 'Credits',
    title: 'Credits and trademarks · Cupola',
    heading: 'Credits.',
    description: 'The open movies that light this site, the typefaces, and the trademarks of the services Cupola connects to.',
    light: 'lamp',
  },
} satisfies Record<string, Page>;

export type PageId = keyof typeof pages;

/** One page per app in rivals.ts, at /alternatives/<id>/. */
export const rivalPages: Page[] = rivals.map((r) => ({
  path: `/alternatives/${r.id}/`,
  slug: `alternative-${r.id}`,
  name: r.name,
  title: r.title,
  heading: r.heading,
  description: r.description,
  light: 'spring',
}));

const serviceLight: Record<Category, LightId> = { Media: 'tos', Downloads: 'charge', Stream: 'sintel', Infrastructure: 'lamp' };

/** One page per service in the README, at /services/<id>/. */
export const servicePages: Page[] = services().map((s) => ({
  path: `/services/${s.id}/`,
  slug: `service-${s.id}`,
  name: s.name,
  title: `${s.name} app for iPhone and Android · Cupola`,
  heading: `${s.name}, from your phone.`,
  description: `Manage ${s.name} from iPhone, Android or Mac with Cupola, free and open source: what it can do, how to connect it, and how well it is tested.`,
  light: serviceLight[s.category],
}));

export const allPages: Page[] = [...Object.values(pages), ...rivalPages, ...servicePages];
