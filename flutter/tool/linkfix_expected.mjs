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
    getItem: function (key) {
      if (store.has(key)) {
        return store.get(key);
      }
      return null;
    },
    setItem: function (key, value) {
      return store.set(key, String(value));
    },
    removeItem: function (key) {
      return store.delete(key);
    },
  },
};
vm.createContext(sandbox);

// Runs inside the sandbox, after script.js, to hand its functions and lists back out. Sets become
// arrays and regular expressions their source text, so they can be written as JSON.
const exportCode = `
function toPlainPlatformTrackers() {
  const plain = {};
  for (const [host, trackerSet] of Object.entries(PLATFORM_TRACKERS)) {
    plain[host] = [...trackerSet];
  }
  return plain;
}
function toPlainPlatformPatterns() {
  const plain = {};
  for (const [host, pattern] of Object.entries(PLATFORM_TRACKER_PATTERNS)) {
    plain[host] = pattern.source;
  }
  return plain;
}
function converterNames() {
  const names = [];
  for (const converter of EMBED_CONVERTERS) {
    names.push(converter.name);
  }
  return names;
}
globalThis.__linkFixer = {
  cleanUrl, extractUrlFromText, replaceLinkInText, isMeaningfulRedirect, urlsEquivalent, detectPlatform,
  TRACKER_PREFIXES, UNIVERSAL_TRACKERS: [...UNIVERSAL_TRACKERS],
  PLATFORM_TRACKERS: toPlainPlatformTrackers(),
  PLATFORM_TRACKER_PATTERNS: toPlainPlatformPatterns(),
  STRIP_ALL_PARAMETER_HOSTS, STRIP_ALL_PARAMETER_PATH, MASTODON_INSTANCES,
  CONVERTERS: converterNames(),
};`;
vm.runInContext(`${source}\n${exportCode}`, sandbox);
const linkFixer = sandbox.__linkFixer;

const cases = JSON.parse(readFileSync(join(root, 'test', 'fixtures', 'linkfix_cases.json'), 'utf8'));

const clean = [];
for (const input of cases.clean) {
  try {
    const result = linkFixer.cleanUrl(input);
    clean.push({
      input,
      cleaned: result.cleaned,
      platform: result.platform,
      wasConverted: result.wasConverted,
      changes: result.changes,
    });
  } catch (error) {
    clean.push({ input, error: error.message });
  }
}

const extract = [];
for (const text of cases.extract) {
  extract.push({ text, url: linkFixer.extractUrlFromText(text) });
}

const redirects = [];
for (const [fromUrl, toUrl] of cases.redirects) {
  redirects.push({
    a: fromUrl,
    b: toUrl,
    meaningful: linkFixer.isMeaningfulRedirect(fromUrl, toUrl),
    equivalent: linkFixer.urlsEquivalent(fromUrl, toUrl),
  });
}

const output = {
  lists: {
    trackerPrefixes: linkFixer.TRACKER_PREFIXES,
    universal: linkFixer.UNIVERSAL_TRACKERS,
    platform: linkFixer.PLATFORM_TRACKERS,
    patterns: linkFixer.PLATFORM_TRACKER_PATTERNS,
    stripAllHosts: linkFixer.STRIP_ALL_PARAMETER_HOSTS,
    stripAllPath: linkFixer.STRIP_ALL_PARAMETER_PATH,
    mastodon: linkFixer.MASTODON_INSTANCES,
    converters: linkFixer.CONVERTERS,
  },
  clean,
  extract,
  redirects,
};
writeFileSync(join(root, 'test', 'fixtures', 'linkfix_expected.json'), `${JSON.stringify(output, null, 1)}\n`);
console.log(`${clean.length} links, ${extract.length} texts, ${redirects.length} redirects`);
