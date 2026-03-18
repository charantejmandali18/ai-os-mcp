# ai-os-mcp v2 — Full Desktop Control for Claude Code

**Date:** 2026-03-18
**Status:** Draft
**Author:** Charan + Claude

## Problem

ai-os-mcp provides Claude Code with macOS accessibility tree access (6 tools), but many apps have poor or no AX tree support — Electron apps, canvas-based UIs, Java apps, and custom-rendered content. Without a fallback, Claude is blind in these apps.

clawdcursor (github.com/AmrDab/clawdcursor) solves this with a 5-layer pipeline, but it wraps its own AI brain around the tools. With Claude Code as the AI brain, we only need the tools — exposed as MCP servers.

## Solution

Enhance ai-os-mcp with 12 new native macOS tools and add a companion Node.js MCP server for browser/Electron control via CDP. Claude Code uses a structured-data-first fallback chain — no screenshots as the primary interaction method.

## Architecture

```
Claude Code (AI Brain)
    |
    +-- ai-os-mcp (Swift, stdio MCP) --- Native macOS control
    |   +-- Existing: AX tree, click, type, press key (6 tools)
    |   +-- New: Scroll, raw mouse, drag (3 tools)
    |   +-- New: Screenshot, app launch, URL open (3 tools)
    |   +-- New: AppleScript/JXA execution (1 tool)
    |   +-- New: Menu bar read + click (2 tools)
    |   +-- New: Pasteboard read/write (2 tools)
    |   +-- New: Window management (1 tool)
    |
    +-- ai-os-browser (Node.js, stdio MCP) --- Browser/Electron control
        +-- Connect to existing Chrome or launch new
        +-- DOM tree reading (structured JSON)
        +-- Click/type/select via CSS selectors
        +-- Page navigation, tab management
        +-- JS execution in page context
        +-- Form filling
```

## Fallback Chain

When Claude interacts with an app, it uses this priority:

1. **AX tree** (existing) — works for most native macOS apps
2. **CDP/DOM** (ai-os-browser) — works for web apps and Electron apps
3. **AppleScript/JXA** — works for scriptable apps (Finder, Mail, Safari, etc.)
4. **Menu bar traversal** — menus are almost always AX-accessible even when content isn't
5. **Keyboard navigation** — tab, arrows, shortcuts
6. **Pasteboard bridge** — Cmd+A, Cmd+C, read clipboard for content extraction
7. **Raw mouse + screenshot** — last resort for truly opaque apps

Claude makes routing decisions naturally — no routing code needed.

## New Swift Tools (ai-os-mcp)

### Scroll

Scroll within an app or specific element.

- **Tool name:** `scroll`
- **Parameters:**
  - `app_name` (string, required) — target app
  - `direction` (enum: up|down|left|right, required)
  - `amount` (number, default 3) — number of scroll increments
  - `element_search` (string, optional) — scroll within a specific element
- **Implementation:** CGEvent scroll wheel events. If element_search provided, find element via AX search, get its position, move mouse there first, then scroll. If element_search is NOT provided: raise the target app, get the frontmost window's position and size, move mouse to window center, then scroll. This ensures scroll events are delivered to the correct window.

### Mouse Click At

Raw coordinate-based click as a fallback when semantic search fails.

- **Tool name:** `mouse_click_at`
- **Parameters:**
  - `x` (number, required) — screen x coordinate (global macOS coordinate system)
  - `y` (number, required) — screen y coordinate
  - `button` (enum: left|right|middle, default left)
  - `click_type` (enum: single|double|triple, default single)
  - `app_name` (string, optional) — raise this app before clicking
- **Implementation:** CGEvent mouse click at absolute screen coordinates. If app_name provided, activate app first.
- **Coordinate system:** macOS global coordinates — primary display origin is (0,0) at top-left. Secondary displays extend into positive/negative X/Y. AX tree element positions and screenshot dimensions use the same coordinate system.

### Mouse Drag

Drag from one point to another.

- **Tool name:** `mouse_drag`
- **Parameters:**
  - `from_x`, `from_y` (number, required)
  - `to_x`, `to_y` (number, required)
  - `duration` (number, default 0.5) — drag duration in seconds for smooth movement
  - `app_name` (string, optional) — raise this app before dragging
- **Implementation:** CGEvent mouse down at from, smooth move to to, mouse up. Coordinates use the global macOS coordinate system.

### Take Screenshot

Capture screen or specific window. Fallback for when structured data isn't available.

- **Tool name:** `take_screenshot`
- **Parameters:**
  - `app_name` (string, optional) — capture specific window. Omit for full screen.
  - `max_width` (integer, default 1280) — max width in pixels, image is scaled to fit
  - `max_height` (integer, default 800) — max height in pixels
  - `format` (enum: png|jpeg, default jpeg) — JPEG is 5-10x smaller
  - `quality` (number, default 0.7) — JPEG quality (0.0-1.0), ignored for PNG
- **Implementation:** CGWindowListCreateImage for window or full screen. Scale to fit within max_width/max_height. Write to temp file at `/tmp/ai-os-mcp-screenshot-{timestamp}.{format}`, return the file path so Claude Code can read it via its own file reading capability. This avoids bloating MCP messages with multi-MB base64 payloads.
- **Cleanup:** Temp files are deleted on next screenshot call.

### Open Application

Launch an application.

- **Tool name:** `open_application`
- **Parameters:**
  - `app_name` (string, required) — app display name or bundle ID (e.g. "Safari" or "com.apple.Safari")
- **Implementation:** Two code paths:
  1. If input contains dots (looks like bundle ID): use `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` to resolve, then `openApplication(at:configuration:)`.
  2. Otherwise: use existing AppResolver for name matching, get the app's URL, then `openApplication(at:configuration:)`.
- **Note:** Does NOT use the existing AppResolver for bundle IDs since it only matches display names.

### Open URL

Open a URL in the default browser.

- **Tool name:** `open_url`
- **Parameters:**
  - `url` (string, required)
- **Implementation:** NSWorkspace.open(URL).

### Manage Window

Resize, move, minimize, or fullscreen a window.

- **Tool name:** `manage_window`
- **Parameters:**
  - `app_name` (string, required)
  - `action` (enum: resize|move|minimize|maximize|fullscreen|restore)
  - `x`, `y` (number, optional) — required for `move`, ignored otherwise
  - `width`, `height` (number, optional) — required for `resize`, ignored otherwise
- **Implementation:** AXUIElement setAttribute for position/size. AXPress for minimize/zoom buttons.
- **macOS semantics:**
  - `maximize` = resize window to fill screen work area without entering fullscreen. Sets AXPosition to {0, menuBarHeight} and AXSize to {screenWidth, screenHeight - menuBarHeight - dockHeight}.
  - `fullscreen` = enter native macOS fullscreen (creates a new Space). Press the AXFullScreen button. May have animation delays (~0.7s).
  - `restore` = exit fullscreen or un-minimize.
- **Validation:** Return clear error if required params are missing (e.g. `resize` without `width`/`height`).

### Run AppleScript

Execute AppleScript or JXA code for scriptable apps.

- **Tool name:** `run_applescript`
- **Parameters:**
  - `script` (string, required) — the script source code
  - `language` (enum: applescript|javascript, default applescript)
- **Implementation:** Process spawn `osascript` (or `osascript -l JavaScript` for JXA) as a subprocess with 30-second timeout via `DispatchQueue.asyncAfter` + `Process.terminate()`.
- **Security considerations:**
  - AppleScript/JXA has full system access — it can read/write files, launch processes, execute shell commands via `do shell script`, and access the network. There is no sandboxing mechanism.
  - Safety relies on Claude Code's permission model — the user is prompted before each tool invocation.
  - Input validation: reject scripts containing `do shell script` or `run shell script` patterns. Log a warning (but don't block) for scripts targeting sensitive apps like Terminal, System Preferences.
  - The 30-second timeout is enforced by killing the osascript subprocess, not by NSAppleScript (which has no built-in timeout).

### Get Menu Bar

Read all menu bar items for an app.

- **Tool name:** `get_menu_bar`
- **Parameters:**
  - `app_name` (string, required)
- **Implementation:** Read AXMenuBar role from app's AX element, recursively enumerate AXMenuBarItem > AXMenu > AXMenuItem hierarchy. Return as structured JSON tree with title, enabled state, shortcut key.

### Click Menu Item

Click a menu item by path.

- **Tool name:** `click_menu_item`
- **Parameters:**
  - `app_name` (string, required)
  - `menu_path` (string, required) — e.g. "File > Export > PDF"
- **Implementation:** Navigate AXMenuBar hierarchy matching each path segment, then AXPress on the final item.
- **Path parsing:** Separator is ` > ` (space-arrow-space). Matching is case-insensitive. Trailing ellipsis characters are normalized (both `...` and `\u2026` stripped before comparison).
- **Error response:** If a segment doesn't match, return an error that includes the available items at the failed level, so Claude can self-correct. E.g. `"Menu item 'Export' not found under 'File'. Available: [New, Open, Open Recent, Close, Save, Save As, Revert To, ...]"`

### Read Pasteboard

Read clipboard contents.

- **Tool name:** `read_pasteboard`
- **Parameters:**
  - `format` (enum: text|html|rtf|file_urls, default text)
- **Implementation:** NSPasteboard.general read for requested type.
- **Return format:** `text`, `html`, `rtf` return the content as a string. `file_urls` returns a JSON array of absolute file path strings, e.g. `["/Users/me/file.txt"]`.
- **Error:** Returns `pasteboardEmpty` error if clipboard has no content of the requested type.

### Write Pasteboard

Write to clipboard.

- **Tool name:** `write_pasteboard`
- **Parameters:**
  - `content` (string, required)
  - `format` (enum: text|html, default text)
- **Implementation:** NSPasteboard.general clear + write.
- **Note:** Write supports fewer formats than read — writing RTF or file URLs programmatically is uncommon and complex. For RTF, use AppleScript targeting a rich text editor instead.

## Error Model

Extend the existing `AIOSError` enum with new cases for the 12 new tools:

```swift
enum AIOSError: Error {
    // Existing
    case permissionDenied
    case appNotFound(name: String)
    case elementNotFound(search: String)
    case appUnresponsive(name: String)
    case invalidParameter(detail: String)
    case axError(detail: String)

    // New
    case scriptTimeout(seconds: Int)
    case scriptError(message: String)
    case scriptBlocked(reason: String)          // dangerous pattern detected
    case menuItemNotFound(path: String, available: [String])
    case pasteboardEmpty(format: String)
    case windowManagementFailed(app: String, action: String, detail: String)
    case invalidURL(url: String)
    case screenshotFailed(detail: String)
    case appLaunchFailed(name: String, detail: String)
}
```

All errors return user-friendly descriptions via `LocalizedError` conformance, matching the existing pattern.

## Configuration

Both MCP servers are registered in Claude Code's settings. Example `~/.claude.json` (or project `.claude/settings.json`):

```json
{
  "mcpServers": {
    "ai-os-mcp": {
      "command": "/Users/charantej/.local/bin/ai-os-mcp",
      "args": []
    },
    "ai-os-browser": {
      "command": "node",
      "args": ["/Users/charantej/.local/lib/ai-os-browser/dist/index.js"]
    }
  }
}
```

For Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "ai-os-mcp": {
      "command": "/Users/charantej/.local/bin/ai-os-mcp"
    },
    "ai-os-browser": {
      "command": "node",
      "args": ["/Users/charantej/.local/lib/ai-os-browser/dist/index.js"]
    }
  }
}
```

Claude Code can call tools from both servers seamlessly — tools are namespaced by server name (e.g., `mcp__ai-os-mcp__click_element` and `mcp__ai-os-browser__browser_click`).

## Version

Bump from `0.1.0` to `0.2.0` to reflect the significant feature addition.

## Node.js Browser Server (ai-os-browser)

### Overview

Lightweight MCP server using Playwright for structured browser/Electron control via CDP. Returns DOM trees as JSON, not screenshots.

### Tools

#### browser_connect

Connect to running Chrome instance or launch new one.

- **Parameters:**
  - `mode` (enum: connect|launch, default connect)
  - `url` (string, optional) — navigate after connecting
  - `cdp_url` (string, optional) — custom CDP endpoint, default `http://localhost:9222`
- **Behavior:** `connect` mode attaches to existing Chrome (user must launch Chrome with `--remote-debugging-port=9222`). `launch` mode starts isolated Chromium via Playwright.

#### browser_navigate

Navigate to URL.

- **Parameters:**
  - `url` (string, required)
  - `wait_until` (enum: load|domcontentloaded|networkidle, default load)

#### browser_get_dom

Read page DOM as structured tree. The structured-data equivalent of a screenshot.

- **Parameters:**
  - `selector` (string, optional) — CSS selector to scope subtree
  - `max_depth` (number, default 8) — SPAs often have deeply nested DOMs; increase if needed
  - `max_children` (number, default 50)
  - `include_attributes` (boolean, default true)
  - `filter` (string, optional) — text content filter
- **Returns:** JSON tree of elements with tag, id, classes, text, role, aria attributes, href, src, visibility, bounds.

#### browser_click

Click element by CSS selector or text content.

- **Parameters:**
  - `selector` (string, optional) — CSS selector
  - `text` (string, optional) — match by visible text
  - `index` (number, default 0) — which match if multiple

#### browser_type

Type into an element.

- **Parameters:**
  - `selector` (string, optional) — CSS selector for target
  - `text` (string, optional) — match input by nearby label/placeholder text
  - `value` (string, required) — what to type
  - `clear_first` (boolean, default true)

#### browser_select

Select dropdown option.

- **Parameters:**
  - `selector` (string, required)
  - `value` (string, required) — option value or visible text

#### browser_fill_form

Fill multiple form fields at once.

- **Parameters:**
  - `fields` (array of {selector, value}, required)
  - `submit` (boolean, default false) — submit form after filling

#### browser_execute_js

Run JavaScript in page context.

- **Parameters:**
  - `script` (string, required)
  - `args` (array, optional) — arguments passed to the function
- **Returns:** Serialized return value.

#### browser_get_text

Extract text content from page or element.

- **Parameters:**
  - `selector` (string, optional) — scope to element

#### browser_get_tabs

List all open tabs/pages.

- **Returns:** Array of {index, url, title, active}.

#### browser_switch_tab

Switch to a different tab.

- **Parameters:**
  - `index` (number, optional)
  - `url_pattern` (string, optional) — regex match against tab URL

## Project Structure

```
ai-os-mcp/
+-- Sources/ai-os-mcp/
|   +-- Tools/                       (6 existing + 12 new)
|   |   +-- GetRunningApps.swift     (existing)
|   |   +-- GetFrontmostApp.swift    (existing)
|   |   +-- GetAXTree.swift          (existing)
|   |   +-- ClickElement.swift       (existing)
|   |   +-- TypeText.swift           (existing)
|   |   +-- PressKey.swift           (existing)
|   |   +-- Scroll.swift             (new)
|   |   +-- MouseClickAt.swift       (new)
|   |   +-- MouseDrag.swift          (new)
|   |   +-- TakeScreenshot.swift     (new)
|   |   +-- OpenApplication.swift    (new)
|   |   +-- OpenURL.swift            (new)
|   |   +-- ManageWindow.swift       (new)
|   |   +-- RunAppleScript.swift     (new)
|   |   +-- GetMenuBar.swift         (new)
|   |   +-- ClickMenuItem.swift      (new)
|   |   +-- ReadPasteboard.swift     (new)
|   |   +-- WritePasteboard.swift    (new)
|   +-- AX/                          (existing, add scroll/mouse helpers)
|   +-- App/                         (existing)
|   +-- Models/                      (existing, extend)
|   +-- Server.swift                 (add new tool registrations)
|
+-- ai-os-browser/                   (new companion Node.js server)
|   +-- package.json
|   +-- tsconfig.json
|   +-- src/
|   |   +-- index.ts                 (MCP server entry, stdio transport)
|   |   +-- browser.ts               (Playwright CDP connection manager)
|   |   +-- tools/
|   |       +-- connect.ts
|   |       +-- navigate.ts
|   |       +-- dom.ts               (get_dom, get_text)
|   |       +-- interact.ts          (click, type, select, fill_form)
|   |       +-- execute.ts           (JS execution)
|   |       +-- tabs.ts
|   +-- scripts/
|       +-- install.sh
|
+-- scripts/
|   +-- install.sh                   (updated: installs both servers)
+-- Tests/                           (existing + new tool tests)
```

## What We Are NOT Building

- No AI brain / agent loop — Claude Code is the brain
- No task decomposition engine — Claude does this naturally
- No multi-provider routing — Claude is the only model
- No web dashboard or REST API — Claude Code CLI is the interface
- No safety tier system — Claude Code has its own permission model
- No keyboard shortcut registry — Claude uses shortcuts contextually
- No cost optimization layers — no per-tool cost with MCP

## Implementation Plan (Parallel Agents)

Work splits into 3 independent streams:

**Stream 1 — Swift: Mouse/Scroll/Screen tools**
Files: Scroll.swift, MouseClickAt.swift, MouseDrag.swift, TakeScreenshot.swift
Dependencies: CGEvent, CGWindowListCreateImage
Tests: ScrollTests, MouseTests, ScreenshotTests

**Stream 2 — Swift: App/Menu/Pasteboard/Script tools**
Files: OpenApplication.swift, OpenURL.swift, ManageWindow.swift, RunAppleScript.swift, GetMenuBar.swift, ClickMenuItem.swift, ReadPasteboard.swift, WritePasteboard.swift
Dependencies: NSWorkspace, NSAppleScript, NSPasteboard, AXMenuBar
Tests: AppLaunchTests, MenuBarTests, PasteboardTests, AppleScriptTests

**Stream 3 — Node.js: ai-os-browser**
Files: entire ai-os-browser/ directory
Dependencies: @anthropic-ai/sdk (MCP), playwright
Tests: DomTests, InteractTests, TabTests

**Final integration (sequential after streams complete):**
- Update Server.swift to register all new tools
- Update install.sh to install both servers
- Update Claude Desktop / Claude Code MCP config
- End-to-end testing across both servers

## Testing Strategy

- Unit tests for each new Swift tool (input validation, error cases)
- Integration tests that interact with Finder/TextEdit (safe, always available)
- Node.js tests using Playwright's built-in test fixtures
- Manual verification of the full fallback chain
