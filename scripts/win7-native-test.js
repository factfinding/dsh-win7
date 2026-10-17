// Loads npm packages with prebuilt native binaries and calls into each one.
// Run from a directory where `npm install koffi bufferutil better-sqlite3` was done.
'use strict';
const path = require('path');
// Resolve packages from the current directory, not from this script's location.
const load = require('module').createRequire(path.join(process.cwd(), 'index.js'));

function version(name) {
  const file = path.join(process.cwd(), 'node_modules', name, 'package.json');
  return JSON.parse(require('fs').readFileSync(file, 'utf8')).version;
}

const results = [];
function check(name, fn) {
  try {
    console.log(`PASS ${name}: ${fn()}`);
    results.push(true);
  } catch (err) {
    console.log(`FAIL ${name}: ${err && err.stack || err}`);
    results.push(false);
  }
}

check('abi', () => `NODE_MODULE_VERSION=${process.versions.modules} napi=${process.versions.napi}`);
check('koffi', () => {
  const koffi = load('koffi');
  const kernel32 = koffi.load('kernel32.dll');
  const GetCurrentProcessId = kernel32.func('uint32 __stdcall GetCurrentProcessId()');
  const pid = GetCurrentProcessId();
  if (pid !== process.pid) throw new Error(`pid ${pid} != ${process.pid}`);
  return `koffi ${version('koffi')}, GetCurrentProcessId ok`;
});
check('bufferutil', () => {
  const bufferutil = load('bufferutil');
  const data = Buffer.from('hello');
  const mask = Buffer.from([1, 2, 3, 4]);
  const out = Buffer.alloc(5);
  bufferutil.mask(data, mask, out, 0, 5);
  bufferutil.unmask(out, mask);
  if (out.toString() !== 'hello') throw new Error('mask/unmask mismatch');
  return `bufferutil ${version('bufferutil')}, mask/unmask ok`;
});
check('better-sqlite3', () => {
  const Database = load('better-sqlite3');
  const db = new Database(':memory:');
  const { v } = db.prepare('select sqlite_version() as v').get();
  db.close();
  return `better-sqlite3 ${version('better-sqlite3')}, sqlite ${v}`;
});

const failed = results.filter((ok) => !ok).length;
console.log(`${results.length - failed}/${results.length} passed`);
process.exitCode = failed ? 1 : 0;
