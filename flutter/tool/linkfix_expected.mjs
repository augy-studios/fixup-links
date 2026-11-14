// Runs the site's own cleaner (main-site/script.js) on every link in test/fixtures/linkfix_cases.json
// and writes what it gives, with its lists, to test/fixtures/linkfix_expected.json, for
// test/linkfix_test.dart to hold the app's port (lib/data/linkfix.dart) to.
//
//   node tool/linkfix_expected.mjs        (from flutter/; again whenever script.js changes)
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const source = readFileSync(join(root, '..', 'main-site', 'script.js'), 'utf8');

// Just enough of a browser for the script to load: its DOM work waits for DOMContentLoaded,
// which never comes here.
const store = new Map();
const sandbox = {
  URL, URLSearchParams, console, AbortSignal, setTimeout, clearTimeout,
  document: { addEventListener() {}, getElementById() { return null; } },
  window: {},
  navigator: {},
  localStorage: {
    getItem: (k) => (store.has(k) ? store.get(k) : null),
    setItem: (k, v) => store.set(k, String(v)),
    removeItem: (k) => store.delete(k),
  },
};
vm.createContext(sandbox);
vm.runInContext(`${source}
globalThis.__lf = {
  cleanUrl, extractUrlFromText, replaceLinkInText, isMeaningfulRedirect, urlsEquivalent, detectPlatform,
  TRACKER_PREFIXES, UNIVERSAL_TRACKERS: [...UNIVERSAL_TRACKERS],
  PLATFORM_TRACKERS: Object.fromEntries(Object.entries(PLATFORM_TRACKERS).map(([k, v]) => [k, [...v]])),
  PLATFORM_TRACKER_PATTERNS: Object.fromEntries(Object.entries(PLATFORM_TRACKER_PATTERNS).map(([k, v]) => [k, v.source])),
  STRIP_ALL_PARAM_HOSTS, STRIP_ALL_PARAM_PATH, MASTODON_INSTANCES,
  CONVERTERS: EMBED_CONVERTERS.map((c) => c.name),
};`, sandbox);
const lf = sandbox.__lf;

const cases = JSON.parse(readFileSync(join(root, 'test', 'fixtures', 'linkfix_cases.json'), 'utf8'));
const clean = cases.clean.map((input) => {
  try {
    const r = lf.cleanUrl(input);
    return { input, cleaned: r.cleaned, platform: r.platform, wasConverted: r.wasConverted, changes: r.changes };
  } catch (e) {
    return { input, error: e.message };
  }
});
const extract = cases.extract.map((text) => ({ text, url: lf.extractUrlFromText(text) }));
const redirects = cases.redirects.map(([a, b]) => ({ a, b, meaningful: lf.isMeaningfulRedirect(a, b), equivalent: lf.urlsEquivalent(a, b) }));

const out = {
  lists: {
    trackerPrefixes: lf.TRACKER_PREFIXES,
    universal: lf.UNIVERSAL_TRACKERS,
    platform: lf.PLATFORM_TRACKERS,
    patterns: lf.PLATFORM_TRACKER_PATTERNS,
    stripAllHosts: lf.STRIP_ALL_PARAM_HOSTS,
    stripAllPath: lf.STRIP_ALL_PARAM_PATH,
    mastodon: lf.MASTODON_INSTANCES,
    converters: lf.CONVERTERS,
  },
  clean,
  extract,
  redirects,
};
writeFileSync(join(root, 'test', 'fixtures', 'linkfix_expected.json'), `${JSON.stringify(out, null, 1)}\n`);
console.log(`${clean.length} links, ${extract.length} texts, ${redirects.length} redirects`);
