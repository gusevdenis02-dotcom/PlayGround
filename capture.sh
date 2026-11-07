#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_URL="${CAPTURE_URL:?Set CAPTURE_URL to the exact preview URL}"
CAPTURE_DIR="${CAPTURE_DIR:?Set CAPTURE_DIR to the evidence output directory}"

run_timed() {
  /usr/bin/time -p "$@"
}

run_timed mkdir -p "$CAPTURE_DIR"
run_timed node --input-type=module <<'NODE'
import { createRequire } from 'node:module';
import { readFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const url = process.env.CAPTURE_URL;
const output = resolve(process.env.CAPTURE_DIR);
const runtime = join(process.env.HOME, '.local/share/omgithub-playwright');
let browser;
let exitCode = 1;
const temporary = (message) => Object.assign(new Error(message), { exitCode: 75 });

try {
  if (!url || !/^https?:\/\//i.test(url)) throw new Error('CAPTURE_URL must be an absolute HTTP(S) URL.');
  await mkdir(output, { recursive: true });
  const require = createRequire(join(runtime, 'package.json'));
  const { chromium } = require('playwright');
  const config = JSON.parse(await readFile(join(runtime, process.platform === 'darwin' ? 'metal.json' : 'linux.json'), 'utf8'));
  if (process.platform === 'linux') {
    try { process.env.DISPLAY ||= ':' + (await readFile(join(runtime, 'display'), 'utf8')).trim(); }
    catch (error) { throw temporary(`Browser display unavailable: ${error.message}`); }
  }
  try { browser = await chromium.launch({ ...config.browser.launchOptions, timeout: 30000 }); }
  catch (error) { throw temporary(`Browser launch failed: ${error.message}`); }

  for (const [name, width, height] of [['desktop', 1440, 900], ['mobile', 390, 844]]) {
    let page;
    try { page = await browser.newPage({ viewport: { width, height } }); }
    catch (error) { throw temporary(`Could not create ${name} browser page: ${error.message}`); }
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    let response;
    try { response = await page.goto(url, { waitUntil: 'load', timeout: 45000 }); }
    catch (error) {
      await page.close().catch(() => {});
      throw temporary(`Navigation failed for ${name}: ${error.message}`);
    }
    if (!response?.ok()) {
      const status = response?.status();
      await page.close().catch(() => {});
      if (!status || [408, 429, 500, 502, 503, 504].includes(status)) {
        throw temporary(`Temporary HTTP ${status ?? 'navigation'} failure loading ${url}`);
      }
      throw new Error(`Preview returned HTTP ${status} for ${url}`);
    }
    await page.locator('body').waitFor({ state: 'visible', timeout: 15000 });
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await page.evaluate(() => document.fonts.ready);
    const rendered = await page.evaluate(() => ({
      text: document.body.innerText.trim(),
      width: document.documentElement.scrollWidth,
      height: document.documentElement.scrollHeight,
    }));
    if (!rendered.text || rendered.width < 1 || rendered.height < 1) {
      throw new Error(`The ${name} page did not render visible application content.`);
    }
    if (pageErrors.length) throw new Error(`The ${name} page raised a rendering error: ${pageErrors.join('; ')}`);
    await page.screenshot({ path: join(output, `final-${name}.png`), fullPage: false, timeout: 30000 });
    console.log(`Captured ${name} (${width}x${height}) from ${url}`);
    await page.close();
  }
  exitCode = 0;
} catch (error) {
  console.error(error);
  exitCode = error.exitCode || 1;
} finally {
  if (browser) {
    try { await browser.close(); }
    catch (error) {
      console.error(`Could not close capture browser: ${error.message}`);
      if (exitCode === 0) exitCode = 75;
    }
  }
}
process.exitCode = exitCode;
NODE
