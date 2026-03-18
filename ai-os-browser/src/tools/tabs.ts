// ai-os-browser/src/tools/tabs.ts
import { getPages, switchToPage } from "../browser.js";

export const getTabsTool = {
  name: "browser_get_tabs",
  description: "List all open browser tabs.",
  inputSchema: { type: "object" as const, properties: {} },
};

export const switchTabTool = {
  name: "browser_switch_tab",
  description: "Switch to a different browser tab.",
  inputSchema: {
    type: "object" as const,
    properties: {
      index: { type: "integer", description: "Tab index (0-based)" },
      url_pattern: { type: "string", description: "Regex pattern to match tab URL" },
    },
  },
};

export async function handleGetTabs() {
  const pages = await getPages();
  const tabs = await Promise.all(
    pages.map(async (p, i) => ({
      index: i,
      url: p.url(),
      title: await p.title(),
    }))
  );
  return { content: [{ type: "text" as const, text: JSON.stringify({ tabs }) }] };
}

export async function handleSwitchTab(args: Record<string, unknown>) {
  const index = args.index as number | undefined;
  const urlPattern = args.url_pattern as string | undefined;
  const page = await switchToPage(index, urlPattern);
  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, url: page.url(), title: await page.title() }) }] };
}
