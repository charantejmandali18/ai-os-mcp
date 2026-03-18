// ai-os-browser/src/browser.ts
import { chromium, type Browser, type BrowserContext, type Page } from "playwright";

let browser: Browser | null = null;
let context: BrowserContext | null = null;

export async function connect(
  mode: "connect" | "launch",
  cdpUrl?: string,
  url?: string
): Promise<{ pages: number; url?: string }> {
  if (browser) {
    // Already connected — just navigate if url provided
    if (url) {
      const page = await getActivePage();
      await page.goto(url);
    }
    const pages = context ? context.pages().length : 0;
    return { pages, url };
  }

  if (mode === "connect") {
    const endpoint = cdpUrl || "http://localhost:9222";
    browser = await chromium.connectOverCDP(endpoint);
    context = browser.contexts()[0] || (await browser.newContext());
  } else {
    browser = await chromium.launch({ headless: false });
    context = await browser.newContext();
  }

  if (url) {
    const page = context.pages()[0] || (await context.newPage());
    await page.goto(url);
  }

  return { pages: context.pages().length, url };
}

export async function getActivePage(): Promise<Page> {
  if (!context) throw new Error("Not connected. Call browser_connect first.");
  const pages = context.pages();
  if (pages.length === 0) {
    return await context.newPage();
  }
  return pages[pages.length - 1];
}

export async function getPages(): Promise<Page[]> {
  if (!context) throw new Error("Not connected. Call browser_connect first.");
  return context.pages();
}

export async function switchToPage(index?: number, urlPattern?: string): Promise<Page> {
  const pages = await getPages();
  if (index !== undefined) {
    if (index < 0 || index >= pages.length) {
      throw new Error(`Tab index ${index} out of range. ${pages.length} tabs open.`);
    }
    await pages[index].bringToFront();
    return pages[index];
  }
  if (urlPattern) {
    const regex = new RegExp(urlPattern);
    const match = pages.find((p) => regex.test(p.url()));
    if (!match) throw new Error(`No tab matching pattern '${urlPattern}'`);
    await match.bringToFront();
    return match;
  }
  throw new Error("Provide either index or url_pattern");
}

export async function disconnect(): Promise<void> {
  if (browser) {
    await browser.close();
    browser = null;
    context = null;
  }
}
