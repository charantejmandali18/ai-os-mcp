// ai-os-browser/src/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { handleConnect } from "./tools/connect.js";
import { handleNavigate } from "./tools/navigate.js";
import { handleGetDom, handleGetText } from "./tools/dom.js";
import { handleClick, handleType, handleSelect, handleFillForm } from "./tools/interact.js";
import { handleExecuteJs } from "./tools/execute.js";
import { handleGetTabs, handleSwitchTab } from "./tools/tabs.js";

const server = new McpServer({
  name: "ai-os-browser",
  version: "0.2.0",
});

// browser_connect
server.tool(
  "browser_connect",
  "Connect to a running Chrome instance via CDP or launch a new browser.",
  {
    mode: z.enum(["connect", "launch"]).optional().describe("connect to existing Chrome or launch new"),
    url: z.string().optional().describe("Navigate to this URL after connecting"),
    cdp_url: z.string().optional().describe("CDP endpoint URL (default: http://localhost:9222)"),
  },
  async (args) => handleConnect(args as Record<string, unknown>)
);

// browser_navigate
server.tool(
  "browser_navigate",
  "Navigate the current page to a URL.",
  {
    url: z.string().describe("URL to navigate to"),
    wait_until: z.enum(["load", "domcontentloaded", "networkidle"]).optional().describe("Wait condition (default: load)"),
  },
  async (args) => handleNavigate(args as Record<string, unknown>)
);

// browser_get_dom
server.tool(
  "browser_get_dom",
  "Read page DOM as a structured JSON tree. Structured-data alternative to screenshots.",
  {
    selector: z.string().optional().describe("CSS selector to scope subtree"),
    max_depth: z.number().optional().describe("Max tree depth (default: 8)"),
    max_children: z.number().optional().describe("Max children per node (default: 50)"),
    filter: z.string().optional().describe("Filter elements by text content"),
  },
  async (args) => handleGetDom(args as Record<string, unknown>)
);

// browser_get_text
server.tool(
  "browser_get_text",
  "Extract text content from the page or a specific element.",
  {
    selector: z.string().optional().describe("CSS selector to scope text extraction"),
  },
  async (args) => handleGetText(args as Record<string, unknown>)
);

// browser_click
server.tool(
  "browser_click",
  "Click an element by CSS selector or visible text.",
  {
    selector: z.string().optional().describe("CSS selector"),
    text: z.string().optional().describe("Match by visible text content"),
    index: z.number().optional().describe("Which match to click (0-indexed, default: 0)"),
  },
  async (args) => handleClick(args as Record<string, unknown>)
);

// browser_type
server.tool(
  "browser_type",
  "Type text into an input element.",
  {
    selector: z.string().optional().describe("CSS selector for the input"),
    text: z.string().optional().describe("Match input by placeholder or label text"),
    value: z.string().describe("Text to type"),
    clear_first: z.boolean().optional().describe("Clear field before typing (default: true)"),
  },
  async (args) => handleType(args as Record<string, unknown>)
);

// browser_select
server.tool(
  "browser_select",
  "Select a dropdown option.",
  {
    selector: z.string().describe("CSS selector for the select element"),
    value: z.string().describe("Option value or visible text"),
  },
  async (args) => handleSelect(args as Record<string, unknown>)
);

// browser_fill_form
server.tool(
  "browser_fill_form",
  "Fill multiple form fields at once.",
  {
    fields: z.array(z.object({
      selector: z.string(),
      value: z.string(),
    })).describe("Array of {selector, value} pairs"),
    submit: z.boolean().optional().describe("Submit form after filling (default: false)"),
  },
  async (args) => handleFillForm(args as Record<string, unknown>)
);

// browser_execute_js
server.tool(
  "browser_execute_js",
  "Execute JavaScript in the page context and return the result.",
  {
    script: z.string().describe("JavaScript code to execute"),
    args: z.array(z.unknown()).optional().describe("Arguments passed to the function"),
  },
  async (args) => handleExecuteJs(args as Record<string, unknown>)
);

// browser_get_tabs
server.tool(
  "browser_get_tabs",
  "List all open browser tabs.",
  {},
  async () => handleGetTabs()
);

// browser_switch_tab
server.tool(
  "browser_switch_tab",
  "Switch to a different browser tab.",
  {
    index: z.number().optional().describe("Tab index (0-based)"),
    url_pattern: z.string().optional().describe("Regex pattern to match tab URL"),
  },
  async (args) => handleSwitchTab(args as Record<string, unknown>)
);

// Start
const transport = new StdioServerTransport();
await server.connect(transport);
