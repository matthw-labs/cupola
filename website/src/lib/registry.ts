// What each service says about itself in the app's own registry
// (lib/features/settings/domain/service_key.dart): its default port, where its
// credential lives, and the caveat the first-run walk shows beside the fields
// (`walkNote`, the short form of the settings screen's `setupNote`). Read from
// the Dart source rather than copied, like the README tables in repo.ts, so a
// service page cannot drift from what the app says. A getter whose shape
// changes fails the build here.
import { readFileSync } from 'node:fs';
import { inRepo } from './paths';

const SOURCE = 'lib/features/settings/domain/service_key.dart';
const CONSTANTS = [
  'lib/features/truenas/domain/truenas_version.dart',
  'lib/features/tracearr/domain/models/tracearr_version.dart',
];

type Value = string | number | null;

const dart = readFileSync(inRepo(SOURCE), 'utf8');

/** The string constants the getters interpolate, such as kTrueNasMinVersion. */
const constants = new Map<string, string>();
for (const file of CONSTANTS) {
  for (const m of readFileSync(inRepo(file), 'utf8').matchAll(/const String (\w+) = '([^']*)';/g)) {
    constants.set(m[1], m[2]);
  }
}

function literal(raw: string, getter: string): Value {
  const value = raw.trim();
  if (value === 'null') return null;
  if (/^\d+$/.test(value)) return Number(value);
  const parts = [...value.matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((m) => m[1]);
  const rest = value.replace(/'((?:[^'\\]|\\.)*)'/g, '').trim();
  if (parts.length === 0 || rest !== '') throw new Error(`${SOURCE}: ${getter} has a value this reader does not know: ${value}`);
  return parts
    .join('')
    .replace(/\$(\w+)/g, (_, name: string) => {
      const c = constants.get(name);
      if (c === undefined) throw new Error(`${SOURCE}: ${getter} interpolates unknown $${name}`);
      return c;
    })
    .replace(/\\(.)/g, '$1');
}

/** One `get <name> => switch (this) { ... };` as a map from enum value to its arm. */
function switchOf(getter: string): Map<string, Value> {
  const start = dart.search(new RegExp(`get ${getter} => switch \\(this\\) \\{`));
  if (start < 0) throw new Error(`${SOURCE}: no switch getter "${getter}"`);
  const open = dart.indexOf('{', start);
  const close = dart.indexOf('\n  };', open);
  const body = dart
    .slice(open + 1, close)
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n');
  const out = new Map<string, Value>();
  for (const arm of body.matchAll(/((?:ServiceKey\.\w+\s*\|\|\s*)*ServiceKey\.\w+)\s*=>\s*([\s\S]*?),\s*(?=ServiceKey\.|$)/g)) {
    const value = literal(arm[2], getter);
    for (const key of arm[1].matchAll(/ServiceKey\.(\w+)/g)) out.set(key[1], value);
  }
  if (out.size !== 19) throw new Error(`${SOURCE}: ${getter} covers ${out.size} services, not 19`);
  return out;
}

export interface Registry {
  /** The enum value, e.g. nginxProxyManager. */
  key: string;
  defaultPort: number;
  /** Where the credential lives in the service's own interface; null for a web login. */
  credentialPath: string | null;
  /** The caveat the first-run walk shows beside the fields, when there is one. */
  setupNote: string | null;
}

let cache: Map<string, Registry> | undefined;

/** The registry entry of the service the README calls [name]. */
export function registryOf(name: string): Registry {
  if (!cache) {
    const titles = switchOf('title');
    const ports = switchOf('defaultPort');
    const paths = switchOf('credentialPath');
    const notes = switchOf('walkNote');
    cache = new Map();
    for (const [key, title] of titles) {
      cache.set(String(title), {
        key,
        defaultPort: Number(ports.get(key)),
        credentialPath: (paths.get(key) as string | null) ?? null,
        setupNote: (notes.get(key) as string | null) ?? null,
      });
    }
  }
  const entry = cache.get(name);
  if (!entry) throw new Error(`${SOURCE}: no ServiceKey titled "${name}" (named so in the README)`);
  return entry;
}
