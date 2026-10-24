// Renders assets/social-preview.html to assets/social-preview.png and docs/og.png (1280x640).
// Needs Playwright with Chromium: npm i -D playwright && npx playwright install chromium
import { chromium } from 'playwright';
import { copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 640 }, deviceScaleFactor: 1 });
await page.goto(`file://${root}assets/social-preview.html`);
await page.screenshot({ path: `${root}assets/social-preview.png` });
copyFileSync(`${root}assets/social-preview.png`, `${root}docs/og.png`);
await browser.close();
