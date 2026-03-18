# ai-os-mcp

A native macOS MCP server that gives Claude Code full desktop control — 22 tools for app automation, plus zero-image screen understanding via Vision OCR.

**No screenshots. No vision models. Pure structured data.**

```
Old way:   Screenshot → Vision Model → Process pixels → Guess coordinates → Click → Miss → Repeat
ai-os-mcp: OCR text+coords (250ms) → Claude reads JSON → click_at(x, y) → Done
```

## What It Does

ai-os-mcp gives Claude Code the ability to see and control any macOS application through:

1. **Vision OCR** — Extracts all on-screen text with pixel coordinates using macOS Vision framework. Works for every app (native, Chromium, Electron). Zero images — Claude processes JSON, not pixels.
2. **Accessibility Tree** — Semantic UI structure for native apps (buttons, menus, text fields with actions).
3. **Direct Control** — Mouse clicks, keyboard input, app launching, window management, AppleScript execution.
4. **Browser Companion** — Separate Node.js MCP server for Playwright-based browser control via CDP.

## Tools (22 native + 11 browser)

### Screen Understanding (Zero Images)

| Tool | Description |
|------|-------------|
| `get_screen` | OCR the screen — returns all text with pixel coordinates as JSON. ~250ms. |
| `act_and_see` | Perform an action AND return OCR result in one call. |
| `run_macro` | Execute multiple actions in ONE call, OCR once at end. Eliminates round-trips. |

### Core Interaction

| Tool | Description |
|------|-------------|
| `get_running_apps` | List all GUI apps with name, PID, bundle ID |
| `get_frontmost_app` | Get the focused app |
| `get_ax_tree` | Read accessibility tree of any app |
| `click_element` | Click element by semantic search (title/ID/description) |
| `type_text` | Type text into focused or found element |
| `press_key` | Keyboard shortcuts (Cmd+C, Return, etc.) |

### Mouse & Scroll

| Tool | Description |
|------|-------------|
| `mouse_click_at` | Click at screen coordinates (from OCR or AX positions) |
| `mouse_drag` | Drag between two points with smooth interpolation |
| `scroll` | Scroll within an app or element |

### App & Window Management

| Tool | Description |
|------|-------------|
| `open_application` | Launch app by name or bundle ID |
| `open_url` | Open URL in default browser |
| `navigate_url` | Open URL in a specific browser (one-call activate + navigate) |
| `manage_window` | Resize, move, minimize, maximize, fullscreen, restore |

### Automation

| Tool | Description |
|------|-------------|
| `run_applescript` | Execute AppleScript or JXA (with safety checks) |
| `get_menu_bar` | Read all menu items for an app |
| `click_menu_item` | Click menu item by path (e.g. "File > Export > PDF") |
| `read_pasteboard` | Read clipboard (text, HTML, RTF, file URLs) |
| `write_pasteboard` | Write to clipboard |
| `take_screenshot` | Capture screen to file (fallback when OCR isn't enough) |

### Browser Companion (ai-os-browser, Node.js)

11 tools via Playwright CDP: `browser_connect`, `browser_navigate`, `browser_get_dom`, `browser_get_text`, `browser_click`, `browser_type`, `browser_select`, `browser_fill_form`, `browser_execute_js`, `browser_get_tabs`, `browser_switch_tab`.

## Quick Start

### Prerequisites

- macOS 13.0+ (Ventura)
- Xcode 16.0+ (Swift 6.0)
- Node.js 20+ (for browser companion, optional)

### Install

```bash
git clone https://github.com/charantejmandali18/ai-os-mcp.git
cd ai-os-mcp
./scripts/install.sh
```

This builds both servers, installs them, and configures Claude Desktop.

### Permissions Required

1. **Accessibility** — System Settings > Privacy & Security > Accessibility > add `~/.local/bin/ai-os-mcp`
2. **Screen Recording** — System Settings > Privacy & Security > Screen Recording > add `ai-os-mcp` (required for `get_screen` / Vision OCR)

### Add to Claude Code

```bash
claude mcp add ai-os-mcp -- ~/.local/bin/ai-os-mcp
```

Or add to `.mcp.json` in your project:
```json
{
  "mcpServers": {
    "ai-os-mcp": {
      "type": "stdio",
      "command": "/Users/YOUR_USERNAME/.local/bin/ai-os-mcp"
    }
  }
}
```

## Usage Examples

**Open a website and click a link:**
```
get_screen                          → see all text + coordinates
act_and_see(app="Dia",              → navigate + return OCR
  action="navigate", url="example.com")
act_and_see(app="Dia",              → click at coords from OCR
  action="click_at", x=1091, y=118)
```

**Play music on Spotify:**
```
open_application(app_name="Spotify")
press_key(key="k", modifiers=["command"], app_name="Spotify")
type_text(text="gym rush", app_name="Spotify")
press_key(key="return", app_name="Spotify")
run_applescript(script='tell application "Spotify" to play')
```

**Create a Google Doc:**
```
navigate_url(app_name="Dia", url="docs.new")
type_text(text="My Document Title\n\nBody content here...", app_name="Dia")
```

## How It Works

### Zero-Image Vision

Instead of screenshots, ai-os-mcp uses a persistent ScreenCaptureKit stream (2 FPS) and macOS Vision framework to OCR the screen:

```
WindowServer → SCStream (2 FPS, in memory) → VNRecognizeTextRequest (~250ms)
                                                    ↓
                                             JSON: [{text: "CONTACT", x: 1056, y: 109, w: 65, h: 14}, ...]
                                                    ↓
                                             Claude reads text, calls click_at(1089, 116)
```

- Frame is always in memory — zero capture latency
- FNV-1a hash detects changes — skip OCR if screen unchanged
- Coordinates scaled to real screen pixels — pass directly to `click_at`
- Claude processes JSON text, not pixels — orders of magnitude faster than vision

### Fallback Chain

1. **Vision OCR** (`get_screen`) — works for ALL apps
2. **AppleScript/JXA** — scriptable apps (browsers, Finder, Mail)
3. **Menu bar** — always accessible even when content isn't
4. **Keyboard** — tab, arrows, shortcuts
5. **Pasteboard** — Cmd+A, Cmd+C, read clipboard
6. **Coordinate click** — `click_at` with OCR coordinates

### Architecture

```
Claude Code (AI Brain)
    ├── ai-os-mcp (Swift, stdio MCP) ── 22 native macOS tools
    │   ├── ScreenCaptureKit + Vision OCR (zero-image screen reading)
    │   ├── Accessibility APIs (semantic element interaction)
    │   ├── CGEvent (mouse, keyboard, scroll)
    │   ├── NSWorkspace (app launch, URL open)
    │   └── AppleScript/JXA (scriptable app automation)
    │
    └── ai-os-browser (Node.js, stdio MCP) ── 11 browser tools
        └── Playwright CDP (DOM access, clicks, typing, JS execution)
```

## Development

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run tests (caution: CGEvent tests send real input)
```

After building, sign and install:
```bash
codesign --force --sign - .build/release/ai-os-mcp
cp .build/release/ai-os-mcp ~/.local/bin/ai-os-mcp
codesign --force --sign - ~/.local/bin/ai-os-mcp
```

## Roadmap

- [x] Accessibility tree tools (v0.1.0)
- [x] Mouse, scroll, screenshot, window management (v0.2.0)
- [x] AppleScript, menu bar, pasteboard (v0.2.0)
- [x] Browser companion via Playwright (v0.2.0)
- [x] Zero-image Vision OCR (v0.3.0)
- [x] act_and_see compound tool (v0.3.0)
- [x] run_macro batch execution (v0.3.0)
- [x] Persistent ScreenCaptureKit stream (v0.3.0)
- [ ] Fix run_macro JSON array parsing
- [ ] AX tree caching (30s TTL)
- [ ] WebSocket transport for remote access

## License

MIT — see [LICENSE](LICENSE)
