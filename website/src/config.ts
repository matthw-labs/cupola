// Every link the site hands out lives here. A download link left null is not
// offered: its platform reads "Not open yet" and the page points at GitHub
// releases instead, so no button leads to a dead end.
const repo = 'https://github.com/matthw-labs/cupola';
// The GitHub release the site offers, by version. Its assets are named
// `cupola-<version>` plus a suffix per platform; move it to the next version
// once that release is published.
const release = '1.1.0-beta';
const asset = (suffix: string) => `${repo}/releases/download/v${release}/cupola-${release}${suffix}`;

export const site = {
  name: 'Cupola',
  url: 'https://get-seekarr.org',
  repo,
  release,
  releases: `${repo}/releases`,
  watch: `${repo}/subscription`,
  issues: `${repo}/issues`,
  contributing: `${repo}/blob/main/CONTRIBUTING.md`,
  kofi: 'https://ko-fi.com/matthwlabs',
  claim: 'A Cupola over your server.',
  promise: 'Nothing left in the dark.',
  description:
    'Cupola is a free, open-source app for Radarr, Sonarr, Seerr, qBittorrent and the rest of your self-hosted media stack, on iPhone, Android and Mac. It talks straight to your own services: no Cupola account, no cloud.',
  // One public TestFlight link serves iPhone, iPad and Mac; everything else is
  // an asset of the release above.
  downloads: {
    testflight: 'https://testflight.apple.com/join/tqmwnCMj' as string | null,
    apk: asset('.apk') as string | null,
    macos: asset('.dmg') as string | null,
    ipa: asset('.ipa') as string | null,
    windows: asset('-windows-x64.zip') as string | null,
    linux: asset('-linux-x64.tar.gz') as string | null,
  },
} as const;
