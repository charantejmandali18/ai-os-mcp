// ai-os-browser/src/tools/interact.ts
import { getActivePage } from "../browser.js";

export const clickTool = {
  name: "browser_click",
  description: "Click an element by CSS selector or visible text.",
  inputSchema: {
    type: "object" as const,
    properties: {
      selector: { type: "string", description: "CSS selector" },
      text: { type: "string", description: "Match by visible text content" },
      index: { type: "integer", description: "Which match to click (0-indexed, default: 0)" },
    },
  },
};

export const typeTool = {
  name: "browser_type",
  description: "Type text into an input element.",
  inputSchema: {
    type: "object" as const,
    properties: {
      selector: { type: "string", description: "CSS selector for the input" },
      text: { type: "string", description: "Match input by placeholder or label text" },
      value: { type: "string", description: "Text to type" },
      clear_first: { type: "boolean", description: "Clear field before typing (default: true)" },
    },
    required: ["value"],
  },
};

export const selectTool = {
  name: "browser_select",
  description: "Select a dropdown option.",
  inputSchema: {
    type: "object" as const,
    properties: {
      selector: { type: "string", description: "CSS selector for the select element" },
      value: { type: "string", description: "Option value or visible text" },
    },
    required: ["selector", "value"],
  },
};

export const fillFormTool = {
  name: "browser_fill_form",
  description: "Fill multiple form fields at once.",
  inputSchema: {
    type: "object" as const,
    properties: {
      fields: {
        type: "array",
        items: {
          type: "object",
          properties: {
            selector: { type: "string" },
            value: { type: "string" },
          },
          required: ["selector", "value"],
        },
        description: "Array of {selector, value} pairs",
      },
      submit: { type: "boolean", description: "Submit form after filling (default: false)" },
    },
    required: ["fields"],
  },
};

export async function handleClick(args: Record<string, unknown>) {
  const page = await getActivePage();
  const selector = args.selector as string | undefined;
  const text = args.text as string | undefined;
  const index = (args.index as number) || 0;

  if (selector) {
    const elements = await page.$$(selector);
    if (elements.length === 0) throw new Error(`No elements found for: ${selector}`);
    if (index >= elements.length) throw new Error(`Index ${index} out of range, found ${elements.length} matches`);
    await elements[index].click();
  } else if (text) {
    const locator = page.getByText(text, { exact: false });
    const count = await locator.count();
    if (count === 0) throw new Error(`No elements with text: ${text}`);
    await locator.nth(index).click();
  } else {
    throw new Error("Provide either selector or text");
  }

  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true }) }] };
}

export async function handleType(args: Record<string, unknown>) {
  const page = await getActivePage();
  const selector = args.selector as string | undefined;
  const text = args.text as string | undefined;
  const value = args.value as string;
  const clearFirst = args.clear_first !== false;

  let target: string;
  if (selector) {
    target = selector;
  } else if (text) {
    target = `input[placeholder*="${text}" i], textarea[placeholder*="${text}" i], [aria-label*="${text}" i]`;
  } else {
    // Type into currently focused element
    if (clearFirst) await page.keyboard.press("Meta+a");
    await page.keyboard.type(value);
    return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, typed: value }) }] };
  }

  if (clearFirst) {
    await page.fill(target, value);
  } else {
    await page.click(target);
    await page.keyboard.type(value);
  }

  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, typed: value }) }] };
}

export async function handleSelect(args: Record<string, unknown>) {
  const page = await getActivePage();
  const selector = args.selector as string;
  const value = args.value as string;
  await page.selectOption(selector, { value }).catch(() =>
    page.selectOption(selector, { label: value })
  );
  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, selected: value }) }] };
}

export async function handleFillForm(args: Record<string, unknown>) {
  const page = await getActivePage();
  const fields = args.fields as Array<{ selector: string; value: string }>;
  const submit = args.submit === true;

  for (const field of fields) {
    await page.fill(field.selector, field.value);
  }

  if (submit) {
    const form = await page.$("form");
    if (form) {
      await page.keyboard.press("Enter");
    }
  }

  return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, filled: fields.length }) }] };
}
