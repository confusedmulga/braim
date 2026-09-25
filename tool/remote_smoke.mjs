// Remote mode end to end: starts tool/phone_harness_test.dart (the real phone
// server over a real SQLite-backed library), opens the phone's address in
// Chromium with a pairing code, and checks: pairing, the Crypt withheld until
// the phone unlocks it, a browser edit landing on the phone, a phone edit
// appearing in the browser, surviving a server restart, and a page reload
// resuming the session without pairing again.
//
//   flutter build web --release --no-web-resources-cdn --pwa-strategy=none
//   node tool/remote_smoke.mjs [build/web] [out-dir]
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const pw = await import('playwright').catch(() =>
  import('/opt/node22/lib/node_modules/playwright/index.mjs'));
const { chromium } = pw.default ?? pw;

const web = resolve(process.argv[2] ?? 'build/web');
const out = resolve(process.argv[3] ?? 'build/remote_smoke');
mkdirSync(out, { recursive: true });
const PORT = 8787 + Math.floor(Math.random() * 500);
const CTL = PORT + 1000;

const harness = spawn('flutter', ['test', 'tool/phone_harness_test.dart'], {
  env: { ...process.env, HARNESS_PORT: `${PORT}`, HARNESS_CONTROL: `${CTL}`, HARNESS_WEB: web },
  stdio: ['ignore', 'pipe', 'pipe'],
});
let harnessLog = '';
await new Promise((res, rej) => {
  const t = setTimeout(() => rej(new Error('harness did not start')), 240000);
  const onData = d => {
    harnessLog += d;
    if (harnessLog.includes('HARNESS READY')) { clearTimeout(t); res(); }
  };
  harness.stdout.on('data', onData);
  harness.stderr.on('data', onData);
  harness.on('exit', c => rej(new Error(`harness exited ${c}\n${harnessLog}`)));
});

const ctl = async (path, body) => {
  const r = await fetch(`http://127.0.0.1:${CTL}${path}`, body
    ? { method: 'POST', body: JSON.stringify(body) } : {});
  return r.json();
};

const failures = [];
const external = new Set();
const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
const context = await browser.newContext({
  viewport: { width: 1440, height: 900 }, locale: 'en-US',
});
const page = await context.newPage();
page.on('pageerror', e => failures.push(`pageerror: ${e.message}`));
page.on('request', r => {
  const u = new URL(r.url());
  if (u.hostname !== '127.0.0.1' && u.protocol.startsWith('http')) external.add(u.origin);
});
const shot = name => page.screenshot({ path: join(out, `${name}.png`) });
const semantics = async () => {
  await page.waitForTimeout(1500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(800);
};
const waitText = (text, timeout = 20000) =>
  page.getByText(text, { exact: false }).first().waitFor({ timeout });

async function until(check, what, timeout = 15000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (await check()) return true;
    await new Promise(r => setTimeout(r, 400));
  }
  failures.push(`timed out waiting for ${what}`);
  return false;
}

try {
  const { code } = await ctl('/code');
  await page.goto(`http://127.0.0.1:${PORT}/#p=${encodeURIComponent(code)}`);
  await page.waitForSelector('flutter-view', { timeout: 60000 });
  await semantics();
  await shot('remote-00-pair');
  if (page.url().includes('#p=')) failures.push('pairing code left in the address bar');
  await page.getByRole('checkbox').first().click();
  await page.getByRole('button', { name: /Allow/ }).click();
  await waitText('Welcome to Braim', 60000);
  await page.waitForTimeout(4000);
  await shot('remote-01-home');
  if (await page.getByText('Phone crypt secret').count()) {
    failures.push('Crypt note reached the browser before unlock');
  }

  // Crypt: ask the phone (auto-approved by the harness).
  await page.getByRole('button', { name: /^Cortex/ }).first().click();
  await page.waitForTimeout(2500);
  await page.getByRole('button', { name: /^Crypt/ }).first().click();
  await waitText('Phone crypt secret');
  await page.waitForTimeout(1500);
  await shot('remote-02-crypt');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(1000);
  await page.getByRole('button', { name: /^Home/ }).first().click();
  await page.waitForTimeout(1500);

  // A note written in the browser lands in the phone's library.
  await page.keyboard.press('Control+n');
  await page.waitForTimeout(2500);
  await page.getByRole('textbox').first().click();
  await page.keyboard.type('From the laptop');
  await page.keyboard.press('Control+Enter');
  await page.waitForTimeout(800);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(1500);
  await until(async () => (await ctl('/notes')).some(n => n.title === 'From the laptop'),
    'the browser note on the phone');

  // A phone edit shows up in the browser.
  const groceries = (await ctl('/notes')).find(n => n.title === 'Groceries');
  await ctl('/edit', { id: groceries.id, title: 'Groceries (edited on phone)' });
  await waitText('Groceries (edited on phone)', 10000).catch(() =>
    failures.push('phone edit did not reach the browser'));
  await page.waitForTimeout(1500);
  await shot('remote-03-live');

  // The server restarts: the page reconnects (remembered computer) and keeps
  // receiving changes.
  await ctl('/restart');
  await page.waitForTimeout(1500);
  await shot('remote-04-reconnecting');
  await ctl('/edit', { id: groceries.id, title: 'Groceries after restart' });
  await waitText('Groceries after restart', 30000).catch(() =>
    failures.push('no live updates after the server restarted'));

  // A reload resumes the session without pairing again.
  await page.reload();
  await page.waitForSelector('flutter-view', { timeout: 60000 });
  await semantics();
  await waitText('Groceries after restart', 30000).catch(() =>
    failures.push('reload did not resume the session'));
  await page.waitForTimeout(2000);
  await shot('remote-05-reloaded');
} catch (e) {
  failures.push(`script: ${e.message}`);
  await shot('remote-error').catch(() => {});
} finally {
  await browser.close();
  await ctl('/stop').catch(() => {});
  setTimeout(() => harness.kill(), 3000);
}

if (external.size) failures.push(`requests left the LAN: ${[...external].join(', ')}`);
console.log(`screenshots in ${out}`);
if (failures.length) {
  console.error(failures.map(f => `FAIL ${f}`).join('\n'));
  process.exit(1);
}
console.log('remote smoke: ok');
process.exit(0);
