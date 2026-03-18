// ai-os-browser/src/tools/execute.ts
import { getActivePage } from "../browser.js";

export const executeJsTool = {
  name: "browser_execute_js",
  description: "Execute JavaScript in the page context and return the result.",
  inputSchema: {
    type: "object" as const,
    properties: {
      script: { type: "string", description: "JavaScript code to execute" },
      args: { type: "array", description: "Arguments passed to the function" },
    },
    required: ["script"],
  },
};

export async function handleExecuteJs(args: Record<string, unknown>) {
  const page = await getActivePage();
  const script = args.script as string;
  const scriptArgs = (args.args as unknown[]) || [];

  const result = await page.evaluate(
    ({ script, args }) => {
      const fn = new Function(...args.map((_: unknown, i: number) => `arg${i}`), script);
      return fn(...args);
    },
    { script, args: scriptArgs }
  );

  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, result }) }] };
}
