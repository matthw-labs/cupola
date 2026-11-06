// The questions people ask about Cupola, answered once. Pages pick from here,
// and so do the FAQPage data and llms-full.txt.
import type { Qa } from '../lib/seo';
import { services } from '../lib/repo';

const s = services();
const verified = s.filter((x) => x.tested === 'verified').length;
const partial = s.filter((x) => x.tested === 'partial').length;
const untested = s.filter((x) => x.tested === 'untested').map((x) => x.name);

export const faq = {
  arrApp: {
    q: 'Is there a Radarr or Sonarr app for iPhone and Android?',
    a: 'Yes. Cupola is a free, open-source app for Radarr, Sonarr, Lidarr and Readarr on iPhone, Android and Mac. It also covers Seerr, the download clients, Jellyfin, Plex, Emby and the server they run on. See <a href="/radarr-sonarr-app/">Radarr and Sonarr on your phone</a>.',
  },
  account: {
    q: 'Does Cupola need a server or an account?',
    a: 'No. There is no Cupola account and no Cupola server. The app talks straight to your own services, and their keys and passwords stay on your device, in the Keychain or the Android Keystore.',
  },
  away: {
    q: 'How do I manage my home server from my phone when I am away?',
    a: 'With the route you already have: a VPN such as WireGuard or Tailscale, or a reverse proxy. Give a connection a second address for when you are out, and Cupola uses whichever one answers.',
  },
  player: {
    q: 'Is Cupola a media player?',
    a: 'No. You still watch in Jellyfin, Plex, Emby or your usual player. Cupola finds, requests and downloads, and shows who is watching, with pause and stop.',
  },
  free: {
    q: 'Is Cupola free?',
    a: 'Yes. It is open source under the Apache License 2.0, with nothing to buy or unlock. If it helps you, a donation on <a href="https://ko-fi.com/matthwlabs">Ko-fi</a> keeps it moving.',
  },
  seerr: {
    q: 'Does it work with Overseerr and Jellyseerr?',
    a: 'Yes. Seerr, Overseerr and Jellyseerr all work the same way in Cupola: Discover, requests, approvals and issues.',
  },
  household: {
    q: 'Can my family request movies without access to Radarr?',
    a: 'Yes. They sign in to Seerr with their own account (email, Jellyfin, Emby or Plex) and get a simpler Cupola: what is ready to watch, Discover and their requests. Invite them from Seerr with a link or a QR code. See <a href="/seerr-requests/">requests with Seerr</a>.',
  },
  leaves: {
    q: 'What data leaves my network?',
    a: 'Two things, and on Android a third. Posters and cast photos come from TMDB, where Seerr points, with none of your credentials attached. A Plex sign-in to Seerr goes through plex.tv once. And on Android, the code scanner in Copy from another device is Google\'s ML Kit, which sends Google diagnostic and usage data; we plan to replace it. We collect nothing ourselves: no analytics, no crash reports. See <a href="/privacy/">privacy</a>.',
  },
  address: {
    q: 'What address do I type for a service?',
    a: 'The address you open its web interface at, port included: <code>http://192.168.1.20:7878</code> for Radarr, or <code>https://radarr.example.com</code> behind a reverse proxy. Without <code>http://</code>, Cupola tries https first. Use the machine\'s address, not a Docker container name.',
  },
  apiKey: {
    q: 'Where do I find the API key?',
    a: 'In the service\'s own web interface, usually under Settings, General. <a href="/services/">Each service\'s page</a> says exactly where, and so does the connection form. qBittorrent, Transmission, NZBGet, Dockge and Nginx Proxy Manager use your normal login instead.',
  },
  discoverSeerr: {
    q: 'Do I need Seerr for Discover?',
    a: 'For most of it. Trending, genres, people, collections and requests come from Seerr. Without it, Discover still shows your calendar and searches your libraries, and the rest of Cupola works as usual.',
  },
  certs: {
    q: 'My services are behind a reverse proxy with a self-signed certificate. Will it work?',
    a: 'Yes. Cupola asks once before trusting a certificate, then pins it to that host. Cloudflare Access tokens, proxy passwords and custom headers work too.',
  },
  tested: {
    q: 'Which services have been tested against real servers?',
    a: `${verified} of ${s.length} have been verified end to end on real servers, and ${partial} partly. ${untested.join(' and ')} ${untested.length === 1 ? 'is' : 'are'} tested against recorded answers only. The <a href="/services/">services page</a> shows which is which.`,
  },
  lunasea: {
    q: 'Is Cupola an alternative to LunaSea?',
    a: 'Yes. It covers what LunaSea did and more, and it is still being developed: LunaSea published its final release and was archived. Your connections need setting up again. See <a href="/alternatives/lunasea/">coming from LunaSea</a>.',
  },
  nzb360: {
    q: 'Is there an nzb360 for iPhone?',
    a: 'nzb360 is Android only. Cupola covers much of the same ground on iPhone, iPad, Mac and Android, and it is free and open source. See <a href="/alternatives/nzb360/">Cupola and nzb360</a>.',
  },
  seekarr: {
    q: 'What happened to Seekarr?',
    a: 'Seekarr is now Cupola. Version 1.0 is a new app, so it installs beside Seekarr and starts empty: add your services again with the same addresses and keys, then remove Seekarr. In Obtainium, remove the Seekarr entry and add Cupola as a new app.',
  },
  widgets: {
    q: 'Are there widgets and notifications?',
    a: 'Yes, on iOS and Android. Widgets show what is coming up, your downloads and your requests. Two notifications, both off until you turn them on: Needs you, when something breaks, and Ready to watch, when your request arrives.',
  },
  desktop: {
    q: 'Does it run on Windows and Linux?',
    a: 'Yes, Windows and Linux builds come with every GitHub release, starting with the first. Nobody has tested them on a real machine yet, so a report helps. There is no web version.',
  },
  english: {
    q: 'Why is Cupola only in English?',
    a: 'It is a choice: the app has no translations. Titles, posters and descriptions still come from your services, in their own language.',
  },
} satisfies Record<string, Qa>;

export type FaqId = keyof typeof faq;
export const pick = (...ids: FaqId[]): Qa[] => ids.map((id) => ({ ...faq[id], id }));
