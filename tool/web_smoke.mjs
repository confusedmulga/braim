// Loads the web build in Chromium, imports a fixture phone backup into the
// browser-local library, walks the main screens and screenshots each, edits a
// note, reloads, and checks the edit survived. Also checks the Crypt note in
// the fixture never reached the browser, and that nothing asks an internet
// host for anything.
//
//   flutter build web --release --no-web-resources-cdn
//   node tool/web_smoke.mjs [build/web] [out-dir]
//
// Uses the Playwright that ships in the container (/opt/node22) or on the
// module path; Chromium comes from PLAYWRIGHT_BROWSERS_PATH.
import { execFileSync } from 'node:child_process';
import { createReadStream, existsSync, mkdirSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, resolve } from 'node:path';

const pw = await import('playwright').catch(() =>
  import('/opt/node22/lib/node_modules/playwright/index.mjs'));
const { chromium } = pw.default ?? pw;

const root = resolve(process.argv[2] ?? 'build/web');
const out = resolve(process.argv[3] ?? 'build/web_smoke');
mkdirSync(out, { recursive: true });

const fixture = join(out, 'fixture.zip');
execFileSync('python3', [resolve('tool/make_fixture_zip.py'), fixture]);

const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.woff2': 'font/woff2', '.frag': 'application/octet-stream',
};
const server = createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  let file = join(root, path);
  if (!file.startsWith(root)) { res.writeHead(403).end(); return; }
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  if (!existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
  createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
const failures = [];
const external = new Set();

async function newPage(context) {
  const page = await context.newPage();
  page.on('pageerror', e => failures.push(`pageerror: ${e.message}`));
  page.on('request', r => {
    const u = new URL(r.url());
    if (!['127.0.0.1', 'localhost'].includes(u.hostname) && u.protocol.startsWith('http')) {
      external.add(u.origin);
    }
  });
  return page;
}

async function boot(page) {
  await page.goto(origin + '/');
  await page.waitForSelector('flt-semantics-placeholder, flutter-view', { timeout: 60000 });
  await page.waitForTimeout(2500);
  // Turn on Flutter's semantics tree so widgets are reachable by role/label.
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(800);
}

const shot = (page, name) => page.screenshot({ path: join(out, `${name}.png`) });
const byText = (page, text) => page.getByText(text, { exact: false }).first();

async function runTheme(scheme) {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 }, locale: 'en-US', colorScheme: scheme,
  });
  const page = await newPage(context);
  await boot(page);
  await shot(page, `${scheme}-00-welcome`);

  // Import the fixture backup.
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: /Import backup from phone/ }).click();
  await (await chooser).setFiles(fixture);
  await byText(page, 'Welcome to Braim').waitFor({ timeout: 30000 });
  // Software GL decodes photos slowly; give the feed time to settle.
  await page.waitForTimeout(5000);
  await shot(page, `${scheme}-01-home`);

  if (await page.getByText('Crypt secret').count()) failures.push('Crypt note reached the browser');

  // Walk the main tabs with the keyboard (→ steps a tab when not typing).
  const tabs = ['sparks', 'narrative', 'journal', 'cortex'];
  for (let i = 0; i < tabs.length; i++) {
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(3500);
    await shot(page, `${scheme}-0${i + 2}-${tabs[i]}`);
  }
  await page.getByRole('button', { name: /^Home/ }).first().click();
  await page.waitForTimeout(2500);

  // Right-click does what a long-press does: the note's quick actions.
  await page.getByRole('button', { name: /^Groceries/ }).first().click({ button: 'right' });
  await page.waitForTimeout(1500);
  await shot(page, `${scheme}-05a-right-click`);
  if (!(await page.getByText('Archive', { exact: false }).count())) {
    failures.push('right-click did not open the quick actions');
  }
  await page.keyboard.press('Escape');
  await page.waitForTimeout(1200);

  // Open a note and come back with Escape.
  await shot(page, `${scheme}-05b-back-home`);
  await page.getByRole('button', { name: /^Groceries/ }).first().click({ timeout: 15000 });
  await page.waitForTimeout(3000);
  await shot(page, `${scheme}-06-note`);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(1000);

  // Settings (side pane → Settings).
  await context.close();
  return page;
}

async function persistence() {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 }, locale: 'en-US',
  });
  const page = await newPage(context);
  await boot(page);
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: /Import backup from phone/ }).click();
  await (await chooser).setFiles(fixture);
  await byText(page, 'Welcome to Braim').waitFor({ timeout: 30000 });

  // New note via Ctrl+N, type, finish with Ctrl+Enter, leave with Escape.
  await page.keyboard.press('Control+n');
  await page.waitForTimeout(2500);
  await page.getByRole('textbox').first().click();
  await page.keyboard.type('Written in the browser');
  await page.waitForTimeout(500);
  await page.keyboard.press('Enter');
  await page.keyboard.type('Body typed on a PC keyboard.');
  await page.waitForTimeout(800);
  await shot(page, 'persist-01-editing');
  await page.keyboard.press('Control+Enter');
  await page.waitForTimeout(1500);
  await shot(page, 'persist-01b-done');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(2500);
  await shot(page, 'persist-02-feed');

  await page.reload();
  await boot(page);
  await page.waitForTimeout(1500);
  await shot(page, 'persist-03-after-reload');
  if (!(await page.getByText('Written in the browser').count())) {
    failures.push('note typed before reload is missing after reload');
  }
  if (!(await page.getByText('Body typed on a PC keyboard').count())) {
    failures.push('note body typed before reload is missing after reload');
  }
  await context.close();
}

try {
  await runTheme('light');
  await runTheme('dark');
  await persistence();
} catch (e) {
  failures.push(`script: ${e.message}`);
} finally {
  await browser.close();
  server.close();
}

if (external.size) failures.push(`requests left the machine: ${[...external].join(', ')}`);
console.log(`screenshots in ${out}`);
if (failures.length) {
  console.error(failures.map(f => `FAIL ${f}`).join('\n'));
  process.exit(1);
}
console.log('web smoke: ok');
