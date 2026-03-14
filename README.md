# ai-os-mcp

A native macOS MCP server that gives AI assistants direct, semantic access to any running application's UI through the Accessibility API.

**No screenshots. No coordinate math. No vision models. Pure structured data.**

```
Traditional AI control:  Screenshot → Vision Model → Guess coordinates → Click → Miss
ai-os-mcp:               AX Tree → AI reads semantics → Acts by element reference → Perfect
```

## What It Does

ai-os-mcp exposes the macOS Accessibility tree — the same structured data screen readers use — as [MCP](https://modelcontextprotocol.io/) tools. Any MCP-compatible AI assistant (Claude Desktop, Claude Code, etc.) can read the live UI of any running app and interact with it semantically.

Instead of: *"There's a green rectangle at roughly x:450, y:320... maybe it's a button?"*

The AI sees:
```json
{
  "role": "AXButton",
  "title": "Play",
  "identifier": "play-button",
  "actions": ["AXPress"],
  "enabled": true
}
```

## Tools

| Tool | Description |
|------|-------------|
| `get_running_apps` | List all running GUI applications with name, PID, and bundle ID |
| `get_frontmost_app` | Get the currently focused application |
| `get_ax_tree` | Read the full semantic UI tree of any app — every button, label, text field, list item |
| `click_element` | Find an element by title/ID/description and click it — no coordinates needed |
| `type_text` | Type text into the focused element or a specific element found by search |
| `press_key` | Send keyboard shortcuts (Cmd+C, Cmd+V, Return, Escape, etc.) |

## Quick Start

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 16.0+ (Swift 6.0)

### Install

```bash
git clone https://github.com/charantejmandali18/ai-os-mcp.git
cd ai-os-mcp
./scripts/install.sh
```

This builds the binary, installs it to `~/.local/bin/ai-os-mcp`, and configures Claude Desktop.

### Manual Setup

**Build:**

```bash
swift build -c release
```

**Add to Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "ai-os-mcp": {
      "command": "/Users/YOUR_USERNAME/.local/bin/ai-os-mcp"
    }
  }
}
```

**Grant Accessibility Permission:**

1. Open **System Settings > Privacy & Security > Accessibility**
2. Click **+** and navigate to the binary at `~/.local/bin/ai-os-mcp`
3. Toggle it **ON**
4. Restart Claude Desktop

## Usage Examples

Once configured, open Claude Desktop and try:

**"What apps are running on my Mac?"**
→ Calls `get_running_apps`, returns structured list

**"Read the Spotify UI"**
→ Calls `get_ax_tree(app_name: "Spotify")`, returns the full sidebar, player controls, playlists

**"Click the 'Good Music' playlist in Spotify"**
→ Calls `click_element(app_name: "Spotify", search: "Good Music")`, finds and clicks it

**"Type 'hello world' in Notes"**
→ Calls `type_text(text: "hello world", app_name: "Notes")`

**"Copy the selected text"**
→ Calls `press_key(key: "c", modifiers: ["command"])`

## Tool Reference

### get_ax_tree

Read an app's accessibility tree.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `app_name` | string | yes | — | App name (case-insensitive, partial match) |
| `max_depth` | int | no | 5 | Max tree depth |
| `max_children` | int | no | 50 | Max children per node |
| `filter` | string | no | — | Only return subtrees matching this text |

### click_element

Find and click a UI element semantically.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `app_name` | string | yes | — | Target app |
| `search` | string | yes | — | Text to match against title, ID, or description |
| `role` | string | no | — | Filter by AX role (e.g., `AXButton`) |
| `index` | int | no | 0 | Which match to click if multiple found |

### type_text

Type text into a UI element.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `text` | string | yes | — | Text to type |
| `app_name` | string | no | — | Bring this app to front first |
| `element_search` | string | no | — | Find and focus this element first |

### press_key

Send a keyboard shortcut.

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `key` | string | yes | — | Key name or single character |
| `modifiers` | string[] | no | [] | `command`, `shift`, `option`, `control` |
| `app_name` | string | no | — | Bring this app to front first |

**Named keys:** `return`, `escape`, `tab`, `space`, `delete`, `up`, `down`, `left`, `right`, `f1`–`f12`, `home`, `end`, `pageup`, `pagedown`

## How It Works

Every macOS application maintains an **Accessibility Tree** — a live, structured representation of its entire UI. This tree was originally built for screen readers (VoiceOver), but it contains everything an AI needs to understand and interact with any application:

```
AXApplication "Spotify"
  └─ AXWindow "Spotify"
       ├─ AXGroup (sidebar)
       │    ├─ AXStaticText "Home"
       │    ├─ AXStaticText "Search"
       │    └─ AXStaticText "Good Music"    ← clickable
       ├─ AXGroup (now playing)
       │    ├─ AXStaticText "Song Title"
       │    ├─ AXButton "Play"              ← clickable
       │    └─ AXSlider "Volume"            ← adjustable
       └─ ...
```

ai-os-mcp reads this tree via the native `AXUIElement` C API (ApplicationServices framework) and exposes it over MCP. The AI reads the tree, understands the semantic structure, and acts on elements by reference — never by pixel coordinates.

## Architecture

```
Claude Desktop / Code ←──stdio (JSON-RPC)──→ ai-os-mcp (Swift binary)
                                                    │
                                              ApplicationServices
                                                    │
                                              macOS AX API
                                                    │
                                              Any running app
```

- **Swift 6.0** with strict concurrency
- **MCP Swift SDK** (modelcontextprotocol/swift-sdk v0.11.0)
- **stdio transport** — Claude launches the binary as a subprocess
- **Non-sandboxed** — required to inspect other apps' accessibility trees

## vs. Screenshot-Based Approaches

| | ai-os-mcp | Screenshot + Vision |
|---|---|---|
| **Speed** | < 200ms | 1–3 seconds |
| **Accuracy** | Exact (node reference) | Approximate (coordinate guess) |
| **Cost** | Zero (no vision model) | Expensive (vision API call) |
| **Reliability** | Deterministic | Probabilistic |
| **Data** | Structured JSON | Raw pixels |
| **Works with** | Any app with AX tree | Only visible UI |

## Development

```bash
swift build          # Debug build
swift build -c release  # Release build
swift test           # Run tests
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Roadmap

- [ ] `scroll_element` — Scroll within scroll areas
- [ ] `get_element_at_position` — Reverse lookup from screen coordinates
- [ ] `watch_element` — Subscribe to UI change notifications
- [ ] `drag_element` — Drag and drop support
- [ ] Tree caching for repeated reads
- [ ] WebSocket transport for remote access

## License

MIT — see [LICENSE](LICENSE)
