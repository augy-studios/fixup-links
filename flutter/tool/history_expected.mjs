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
const out = {
  sanitize: cases.sanitize.map((input) => ({ input, output: sanitize(input) })),
  merge: cases.merge.map(({ name, mine, theirs }) => ({ name, mine, theirs, ...merge(mine, theirs) })),
};
writeFileSync(join(root, 'test', 'fixtures', 'history_expected.json'), `${JSON.stringify(out, null, 1)}\n`);
console.log(`${out.sanitize.length} entries, ${out.merge.length} merges`);
