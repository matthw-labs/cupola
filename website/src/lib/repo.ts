// Reads facts from the repository instead of copying them: the services
// tables from the README, the service marks from tool/service_glyphs and the
// brand mark from assets/brand. A README whose tables change shape fails the
// build here rather than publishing a page that drifted from the app.
import { readFileSync } from 'node:fs';
import { inRepo } from './paths';
import { site } from '../config';

const read = (path: string) => readFileSync(inRepo(path), 'utf8');

export type Tested = 'verified' | 'partial' | 'untested';
export type Category = 'Media' | 'Downloads' | 'Stream' | 'Infrastructure';

export interface Service {
  id: string;
  name: string;
  aka?: string;
  category: Category;
  what: string;
  auth: string;
  control: string;
  tested: Tested;
  note?: string;
}

const GLYPH: Record<string, string> = {
  'Nginx Proxy Manager': 'nginx_proxy_manager',
};

export const idOf = (name: string) =>
  GLYPH[name] ?? name.toLowerCase().replace(/[^a-z0-9]+/g, '');

const testedOf = (cell: string): Tested => {
  if (cell.includes('✅')) return 'verified';
  if (cell.includes('◐')) return 'partial';
  if (cell.includes('○')) return 'untested';
  throw new Error(`README: unknown Tested mark "${cell}"`);
};

let cache: Service[] | undefined;

export function services(): Service[] {
  if (cache) return cache;
  const md = read('README.md');
  const start = md.indexOf('## Supported services');
  const end = md.indexOf('\n## ', start + 5);
  if (start < 0 || end < 0) throw new Error('README: no "Supported services" section');
  const section = md.slice(start, end);
  const footnotes = new Map<string, string>();
  for (const para of section.split(/\n\s*\n/)) {
    const m = para.trim().match(/^([¹²³])\s+([\s\S]+)$/);
    if (m) footnotes.set(m[1], m[2].replace(/\s*\n\s*/g, ' ').trim());
  }
  const out: Service[] = [];
  let category: Category | undefined;
  for (const line of section.split('\n')) {
    const heading = line.match(/^### (Media|Downloads|Stream|Infrastructure)\s*$/);
    if (heading) {
      category = heading[1] as Category;
      continue;
    }
    const row = line.match(/^\|\s*\*\*(.+?)\*\*\s*(\((.+?)\))?\s*\|(.+)\|\s*$/);
    if (!row || !category) continue;
    const cells = row[4].split('|').map((c) => c.trim());
    if (cells.length !== 4) throw new Error(`README: row "${row[1]}" has ${cells.length + 1} cells`);
    const [what, auth, control, testedCell] = cells;
    const mark = testedCell.match(/[¹²³]/)?.[0];
    out.push({
      id: idOf(row[1]),
      name: row[1],
      aka: row[3],
      category,
      what,
      auth,
      control,
      tested: testedOf(testedCell),
      note: mark ? footnotes.get(mark) : undefined,
    });
  }
  if (out.length !== 19) throw new Error(`README: expected 19 services, read ${out.length}`);
  cache = out;
  return out;
}

export const serviceNamed = (name: string) => {
  const s = services().find((x) => x.name === name);
  if (!s) throw new Error(`No service named ${name} in the README`);
  return s;
};

/** A service mark as inline SVG that takes the text colour. */
export function glyph(id: string): string {
  const svg = read(`tool/service_glyphs/svg/${id}.svg`);
  const paths = svg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').replace(/<title>.*?<\/title>/, '');
  return `<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false">${paths}</svg>`;
}

export const brandSvg = (file: 'cupola_mark' | 'cupola_icon' | 'cupola_launcher') =>
  read(`assets/brand/${file}.svg`);

/** The GitHub star count at build time, or null when GitHub did not answer. */
let starsOnce: Promise<number | null> | undefined;
export const stars = () => (starsOnce ??= fetchStars());

async function fetchStars(): Promise<number | null> {
  try {
    const res = await fetch(site.repo.replace('https://github.com/', 'https://api.github.com/repos/'), {
      headers: { Accept: 'application/vnd.github+json' },
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return null;
    const json = (await res.json()) as { stargazers_count?: number };
    return typeof json.stargazers_count === 'number' ? json.stargazers_count : null;
  } catch {
    return null;
  }
}
