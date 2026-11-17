// Runs the site's history merge (main-site/js/history-merge.js) on the cases in
// test/fixtures/history_cases.json and writes what it gives to test/fixtures/history_expected.json,
// for test/history_test.dart to hold the app's (lib/data/history.dart) to: shared history has to
// come out the same on every device.
//
//   node tool/history_expected.mjs        (from flutter/)
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const sandbox = { window: {}, Date, Number, Array, Map, Set, JSON };
vm.createContext(sandbox);
vm.runInContext(readFileSync(join(root, '..', 'main-site', 'js', 'history-merge.js'), 'utf8'), sandbox);
const { merge, sanitize } = sandbox.window.HistoryMerge;

const cases = JSON.parse(readFileSync(join(root, 'test', 'fixtures', 'history_cases.json'), 'utf8'));

// Each sanitize case with what the site gives for it, and each merge case with the merge's result
// alongside its two sides.
const sanitizeResults = [];
for (const input of cases.sanitize) {
  sanitizeResults.push({ input, output: sanitize(input) });
}
const mergeResults = [];
for (const { name, mine, theirs } of cases.merge) {
  mergeResults.push({ name, mine, theirs, ...merge(mine, theirs) });
}
const expected = {
  sanitize: sanitizeResults,
  merge: mergeResults,
};
writeFileSync(join(root, 'test', 'fixtures', 'history_expected.json'), `${JSON.stringify(expected, null, 1)}\n`);
console.log(`${expected.sanitize.length} entries, ${expected.merge.length} merges`);
