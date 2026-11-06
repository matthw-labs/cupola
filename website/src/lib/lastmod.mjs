// When each page last changed, for the sitemap: the date of the last commit
// that touched the page's own source, or the data that is its substance (the
// questions of /faq/, the facts of the comparisons, the README's table of
// services). Shared pieces such as the
// layout or the page titles are left out on purpose, or every edit to them
// would mark all eighteen pages changed and search engines would learn to
// ignore the date.
//
// A shallow clone knows one commit, which would date every page the same: in
// that case, or without git at all, no page gets a date rather than a false one.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const siteDir = fileURLToPath(new URL('../../', import.meta.url));
const git = (...args) =>
  execFileSync('git', args, { cwd: siteDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();

let usable = false;
try {
  usable = git('rev-parse', '--is-shallow-repository') === 'false';
} catch {
  usable = false;
}

const extras = [
  [/^\/faq\/$/, ['src/data/faq.ts']],
  [/^\/alternatives\//, ['src/data/rivals.ts']],
  [/^\/services\/$/, ['../README.md']],
  [/^\/services\/.+\/$/, ['../README.md', '../lib/features/settings/domain/service_key.dart']],
];

/** The source files of the page at [path] (`/`, `/faq/`, `/alternatives/lunasea/`). */
function sourcesOf(path) {
  const parts = path.split('/').filter(Boolean);
  const name = parts.join('/');
  const candidates = [
    `src/pages/${name || 'index'}.astro`,
    `src/pages/${name}/index.astro`,
  ];
  if (parts.length > 1) candidates.push(`src/pages/${parts.slice(0, -1).join('/')}/[id].astro`);
  const page = candidates.find((file) => existsSync(siteDir + file));
  if (!page) return [];
  return [page, ...extras.filter(([match]) => match.test(path)).flatMap(([, files]) => files)];
}

/** The ISO date [url] last changed, or undefined when it cannot be known. */
export function lastModified(url) {
  if (!usable) return undefined;
  const files = sourcesOf(new URL(url).pathname);
  if (files.length === 0) return undefined;
  try {
    return git('log', '-1', '--format=%cI', '--', ...files) || undefined;
  } catch {
    return undefined;
  }
}
