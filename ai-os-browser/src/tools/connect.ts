// ai-os-browser/src/tools/connect.ts
import { connect } from "../browser.js";

export const connectTool = {
  name: "browser_connect",
  description: "Connect to a running Chrome instance via CDP or launch a new browser.",
  inputSchema: {
    type: "object" as const,
    properties: {
      mode: { type: "string", enum: ["connect", "launch"], description: "connect to existing Chrome or launch new" },
      url: { type: "string", description: "Navigate to this URL after connecting" },
      cdp_url: { type: "string", description: "CDP endpoint URL (default: http://localhost:9222)" },
    },
  },
};

export async function handleConnect(args: Record<string, unknown>) {
  const mode = (args.mode as "connect" | "launch") || "connect";
  const url = args.url as string | undefined;
  const cdpUrl = args.cdp_url as string | undefined;
  const result = await connect(mode, cdpUrl, url);
  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, ...result }) }] };
}
