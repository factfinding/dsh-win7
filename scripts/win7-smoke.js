// Smoke test for a Windows 7 Node.js build (HANDOFF.md, Phase 1 step 7).
// Usage: node win7-smoke.js   Prints one line per check; exits 1 if any fail.
'use strict';
const os = require('os');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const { Worker } = require('worker_threads');

const results = [];
async function check(name, fn) {
  try {
    const value = await fn();
    results.push(true);
    console.log(`PASS ${name}: ${value}`);
  } catch (err) {
    results.push(false);
    console.log(`FAIL ${name}: ${err && err.stack || err}`);
  }
}

(async () => {
  await check('version', () => `${process.version} ${process.arch} openssl=${process.versions.openssl} uv=${process.versions.uv} v8=${process.versions.v8}`);
  await check('os.release', () => `${os.release()} ${os.version ? os.version() : ''}`);
  await check('os.hostname', () => os.hostname());
  await check('process.title', () => process.title);
  await check('hrtime.bigint', () => {
    const a = process.hrtime.bigint();
    const b = process.hrtime.bigint();
    if (b < a) throw new Error('not monotonic');
    return `${b - a}ns`;
  });
  await check('Date.now', () => new Date().toISOString());
  await check('performance.now', () => performance.now().toFixed(3));
  await check('fs', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'smoke-'));
    const file = path.join(dir, 'a.txt');
    fs.writeFileSync(file, 'hello');
    const text = fs.readFileSync(file, 'utf8');
    fs.rmSync(dir, { recursive: true });
    return text;
  });
  await check('fs.watch', () => {
    const w = fs.watch(os.tmpdir());
    w.close();
    return 'ok';
  });
  await check('child_process', () => execFileSync(process.execPath, ['-e', 'process.stdout.write("child ok")']).toString());
  await check('child_process cmd', () => execFileSync('cmd.exe', ['/c', 'echo cmd ok']).toString().trim());
  await check('worker_threads', () => new Promise((resolve, reject) => {
    const w = new Worker('require("worker_threads").parentPort.postMessage(6 * 7)', { eval: true });
    w.once('message', (v) => { resolve(String(v)); w.terminate(); });
    w.once('error', reject);
  }));
  await check('crypto.sha256', () => crypto.createHash('sha256').update('abc').digest('hex'));
  await check('crypto.randomBytes', () => crypto.randomBytes(8).toString('hex'));
  await check('crypto.randomUUID', () => crypto.randomUUID());
  await check('crypto.generateKeyPair', () => crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' }).publicKey.asymmetricKeyType);
  await check('tls.rootCertificates', () => require('tls').rootCertificates.length);
  await check('Intl', () => new Intl.DateTimeFormat('zh-CN', { dateStyle: 'full' }).format(new Date(0)));
  await check('dns.lookup', () => new Promise((resolve, reject) => {
    require('dns').lookup('localhost', (err, addr) => err ? reject(err) : resolve(addr));
  }));
  await check('net server', () => new Promise((resolve, reject) => {
    const net = require('net');
    const srv = net.createServer((s) => s.end('pong')).listen(0, '127.0.0.1', () => {
      const c = net.connect(srv.address().port, '127.0.0.1');
      let data = '';
      c.on('data', (d) => { data += d; });
      c.on('end', () => { srv.close(); resolve(data); });
      c.on('error', reject);
    });
  }));
  await check('zlib', () => require('zlib').gunzipSync(require('zlib').gzipSync('zip ok')).toString());

  const failed = results.filter((ok) => !ok).length;
  console.log(`${results.length - failed}/${results.length} passed`);
  process.exitCode = failed ? 1 : 0;
})();
