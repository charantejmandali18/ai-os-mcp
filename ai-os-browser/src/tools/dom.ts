// ai-os-browser/src/tools/dom.ts
import { getActivePage } from "../browser.js";

export const getDomTool = {
  name: "browser_get_dom",
  description: "Read page DOM as a structured JSON tree. Structured-data alternative to screenshots.",
  inputSchema: {
    type: "object" as const,
    properties: {
      selector: { type: "string", description: "CSS selector to scope subtree" },
      max_depth: { type: "integer", description: "Max tree depth (default: 8)" },
      max_children: { type: "integer", description: "Max children per node (default: 50)" },
      filter: { type: "string", description: "Filter elements by text content" },
    },
  },
};

export const getTextTool = {
  name: "browser_get_text",
  description: "Extract text content from the page or a specific element.",
  inputSchema: {
    type: "object" as const,
    properties: {
      selector: { type: "string", description: "CSS selector to scope text extraction" },
    },
  },
};

interface DomNode {
  tag: string;
  id?: string;
  classes?: string[];
  text?: string;
  role?: string;
  href?: string;
  src?: string;
  type?: string;
  placeholder?: string;
  value?: string;
  visible?: boolean;
  children?: DomNode[];
}

export async function handleGetDom(args: Record<string, unknown>) {
  const page = await getActivePage();
  const selector = args.selector as string | undefined;
  const maxDepth = (args.max_depth as number) || 8;
  const maxChildren = (args.max_children as number) || 50;
  const filter = args.filter as string | undefined;

  const tree = await page.evaluate(
    ({ selector, maxDepth, maxChildren, filter }) => {
      function buildTree(el: Element, depth: number): any {
        if (depth <= 0) return null;

        const tag = el.tagName.toLowerCase();
        // Skip script/style/noscript
        if (["script", "style", "noscript", "svg", "path"].includes(tag)) return null;

        const node: any = { tag };

        if (el.id) node.id = el.id;
        const classes = Array.from(el.classList);
        if (classes.length > 0) node.classes = classes;

        const role = el.getAttribute("role");
        if (role) node.role = role;
        const href = el.getAttribute("href");
        if (href) node.href = href;
        const src = el.getAttribute("src");
        if (src) node.src = src;
        const type = el.getAttribute("type");
        if (type) node.type = type;
        const placeholder = el.getAttribute("placeholder");
        if (placeholder) node.placeholder = placeholder;
        const ariaLabel = el.getAttribute("aria-label");
        if (ariaLabel) node.ariaLabel = ariaLabel;

        // Direct text content (not from children)
        const directText = Array.from(el.childNodes)
          .filter((n) => n.nodeType === Node.TEXT_NODE)
          .map((n) => n.textContent?.trim())
          .filter((t) => t)
          .join(" ");
        if (directText) node.text = directText.substring(0, 200);

        // Value for inputs
        if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
          if (el.value) node.value = el.value.substring(0, 200);
        }

        // Children
        const childElements = Array.from(el.children).slice(0, maxChildren);
        const childNodes = childElements
          .map((c) => buildTree(c, depth - 1))
          .filter((c) => c !== null);
        if (childNodes.length > 0) node.children = childNodes;

        // Filter
        if (filter) {
          const nodeText = JSON.stringify(node).toLowerCase();
          if (!nodeText.includes(filter.toLowerCase()) && (!node.children || node.children.length === 0)) {
            return null;
          }
        }

        return node;
      }

      const root = selector ? document.querySelector(selector) : document.body;
      if (!root) return { error: `No element found for selector: ${selector}` };
      return buildTree(root, maxDepth);
    },
    { selector, maxDepth, maxChildren, filter }
  );

  return { content: [{ type: "text" as const, text: JSON.stringify(tree, null, 2) }] };
}

export async function handleGetText(args: Record<string, unknown>) {
  const page = await getActivePage();
  const selector = args.selector as string | undefined;

  let text: string;
  if (selector) {
    const el = await page.$(selector);
    if (!el) return { content: [{ type: "text" as const, text: JSON.stringify({ error: `No element found for: ${selector}` }) }] };
    text = (await el.textContent()) || "";
  } else {
    text = await page.evaluate(() => document.body.innerText);
  }

  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, text: text.substring(0, 10000) }) }] };
}
