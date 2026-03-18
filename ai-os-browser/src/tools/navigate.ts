// ai-os-browser/src/tools/navigate.ts
import { getActivePage } from "../browser.js";

export const navigateTool = {
  name: "browser_navigate",
  description: "Navigate the current page to a URL.",
  inputSchema: {
    type: "object" as const,
    properties: {
      url: { type: "string", description: "URL to navigate to" },
      wait_until: { type: "string", enum: ["load", "domcontentloaded", "networkidle"], description: "Wait condition (default: load)" },
    },
    required: ["url"],
  },
};

export async function handleNavigate(args: Record<string, unknown>) {
  const page = await getActivePage();
  const url = args.url as string;
  const waitUntil = (args.wait_until as "load" | "domcontentloaded" | "networkidle") || "load";
  await page.goto(url, { waitUntil });
  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, url, title: await page.title() }) }] };
}
