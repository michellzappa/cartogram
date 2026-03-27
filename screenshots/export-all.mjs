#!/usr/bin/env node
// Exports all App Store screenshots (3 slides × 4 sizes = 12 PNGs) via Playwright.
// Requires the dev server running on port 3000: pnpm dev

import { chromium } from "playwright";
import { mkdirSync } from "fs";
import { join } from "path";

const EXPORTS_DIR = join(import.meta.dirname, "exports");
mkdirSync(EXPORTS_DIR, { recursive: true });

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ acceptDownloads: true });
const page = await context.newPage();

console.log("Opening screenshot generator...");
await page.goto("http://localhost:3000", { waitUntil: "networkidle" });

// Click "Export All Sizes" and capture all downloads
console.log("Clicking Export All Sizes...");
const exportBtn = page.locator("button", { hasText: "Export All Sizes" });
await exportBtn.waitFor({ state: "visible" });

// Set up download listener before clicking
const downloads = [];
page.on("download", (download) => {
  downloads.push(download);
});

await exportBtn.click();

// Wait for the button to go back to non-disabled state (export finished)
console.log("Waiting for exports to complete...");
await page.waitForFunction(
  () => {
    const btns = document.querySelectorAll("button");
    for (const btn of btns) {
      if (btn.textContent.includes("Export All Sizes") && !btn.disabled) return true;
    }
    return false;
  },
  { timeout: 300_000 }
);

// Small delay to ensure last download is captured
await page.waitForTimeout(1000);

console.log(`Captured ${downloads.length} downloads. Saving...`);

for (const download of downloads) {
  const name = download.suggestedFilename();
  const dest = join(EXPORTS_DIR, name);
  await download.saveAs(dest);
  console.log(`  ${name}`);
}

await browser.close();
console.log(`\nDone! ${downloads.length} screenshots saved to exports/`);
