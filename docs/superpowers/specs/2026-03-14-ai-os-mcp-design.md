# AI-OS MCP Server — Phase 0 Design Specification

**Date:** 2026-03-14
**Author:** Charan Tej Mandali
**Status:** Approved

---

## 1. Overview

A native macOS MCP (Model Context Protocol) server that gives AI assistants direct, semantic access to any running application's UI through the macOS Accessibility API. No screenshots, no pixel guessing, no coordinate math — pure structured data.

### Problem

Every existing AI computer-control tool (Anthropic Computer Use, OpenAI Operator, Google Project Mariner) follows the same broken pattern:

```
Screenshot → Vision Model → Guess coordinates → Click → Miss
```

This is slow (1–3s), imprecise, expensive, and architecturally wrong.

### Solution

```
macOS AX Tree (semantic, live, real-time) → AI reads directly → Acts by element reference → Perfect, instant
```

The Accessibility API provides a complete, structured, real-time representation of every UI element on screen — the same data screen readers use. This server exposes that data as MCP tools that Claude (or any MCP-compatible AI) can call directly.

---

## 2. Architecture

```
┌─────────────────────────────┐
│  Claude Desktop / Code      │
│  (MCP Client)               │
└──────────┬──────────────────┘
           │ stdio (JSON-RPC)
           ▼
┌─────────────────────────────┐
│  ai-os-mcp                  │
│  Swift executable           │
│                             │
│  ┌───────────────────────┐  │
│  │ MCP Server Layer      │  │
│  │ (swift-sdk, stdio)    │  │
│  └──────────┬────────────┘  │
│             │               │
│  ┌──────────▼────────────┐  │
│  │ Tool Handlers         │  │
│  │ get_ax_tree           │  │
│  │ click_element         │  │
│  │ type_text             │  │
│  │ press_key             │  │
│  │ get_running_apps      │  │
│  │ get_frontmost_app     │  │
│  └──────────┬────────────┘  │
│             │               │
│  ┌──────────▼────────────┐  │
│  │ AX Engine             │  │
│  │ Tree reader           │  │
│  │ Element search        │  │
│  │ Action executor       │  │
│  └──────────┬────────────┘  │
│             │               │
│  ┌──────────▼────────────┐  │
│  │ App Resolver          │  │
│  │ NSWorkspace lookup    │  │
│  │ PID management        │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
           │
           ▼ ApplicationServices.framework
┌─────────────────────────────┐
│  macOS Accessibility API    │
│  (AXUIElement C API)        │
└─────────────────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  Any running application    │
│  (Spotify, Chrome, etc.)    │
└─────────────────────────────┘
```

### Technology Stack

| Component | Technology | Version |
|---|---|---|
| Language | Swift | 6.0+ |
| MCP SDK | modelcontextprotocol/swift-sdk | 0.11.0 |
| Transport | stdio (JSON-RPC over stdin/stdout) | — |
| AX API | ApplicationServices.framework | macOS 13+ |
| App discovery | AppKit (NSWorkspace) | macOS 13+ |
| Keystroke sim | CoreGraphics (CGEvent) | macOS 13+ |
| Build system | Swift Package Manager | — |
| Min macOS | 13.0 (Ventura) | — |

### Non-sandboxed

The binary is **not sandboxed**. The macOS Accessibility API cannot inspect other processes from a sandboxed app. This means:

- No Mac App Store distribution
- Distributed as a compiled binary or built from source
- User grants Accessibility permission once in System Settings

### Concurrency Model

All AX API calls (`AXUIElementCopyAttributeValue`, `AXUIElementPerformAction`, etc.) are synchronous and blocking. To avoid blocking the MCP server's async event loop under Swift 6 strict concurrency, all AX operations are dispatched to a dedicated serial `DispatchQueue` (`axQueue`). The MCP tool handlers bridge async ↔ sync at this boundary.

### Startup Permission Guard

On launch, the server calls `AXIsProcessTrustedWithOptions` with prompt enabled. If accessibility is not granted, the server logs setup instructions to stderr and returns `PERMISSION_DENIED` errors on all tool calls until the user grants permission.

---

## 3. MCP Tools

### 3.1 `get_running_apps`

Lists all GUI applications currently running.

**Input:** None

**Output:**
```json
{
  "apps": [
    {
      "name": "Spotify",
      "pid": 1234,
      "bundleId": "com.spotify.client",
      "isActive": true
    },
    {
      "name": "Google Chrome",
      "pid": 5678,
      "bundleId": "com.google.Chrome",
      "isActive": false
    }
  ]
}
```

**Implementation:** Iterates `NSWorkspace.shared.runningApplications` filtered to `.activationPolicy == .regular` (GUI apps only).

---

### 3.2 `get_frontmost_app`

Returns the currently focused application.

**Input:** None

**Output:**
```json
{
  "name": "Spotify",
  "pid": 1234,
  "bundleId": "com.spotify.client"
}
```

**Implementation:** `NSWorkspace.shared.frontmostApplication`

---

### 3.3 `get_ax_tree`

Reads the full semantic UI tree of any running application.

**Input:**
| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `app_name` | String | Yes | — | App name (case-insensitive, partial match). If multiple apps match, the frontmost is preferred. |
| `max_depth` | Int | No | 5 | Max traversal depth |
| `max_children` | Int | No | 50 | Max children per node (prevents explosion on large lists) |
| `filter` | String | No | — | Only return subtrees containing elements matching this text (title/identifier/description) |

**Output:** Recursive JSON tree of AX nodes:
```json
{
  "app": "Spotify",
  "pid": 1234,
  "tree": {
    "role": "AXApplication",
    "title": "Spotify",
    "children": [
      {
        "role": "AXWindow",
        "title": "Spotify",
        "position": {"x": 0, "y": 25},
        "size": {"width": 1440, "height": 875},
        "children": [
          {
            "role": "AXGroup",
            "identifier": "sidebar",
            "children": [
              {
                "role": "AXStaticText",
                "title": "Good music",
                "actions": ["AXPress"],
                "enabled": true
              }
            ]
          }
        ]
      }
    ]
  }
}
```

**AX Node Schema:**
```json
{
  "role": "String — AX role (AXButton, AXStaticText, etc.)",
  "title": "String? — display title",
  "value": "Any? — current value (text content, slider pos, etc.)",
  "identifier": "String? — developer-assigned ID",
  "description": "String? — accessibility description",
  "roleDescription": "String? — localized role name",
  "position": {"x": "Float", "y": "Float"},
  "size": {"width": "Float", "height": "Float"},
  "actions": ["String — available actions"],
  "enabled": "Bool",
  "focused": "Bool",
  "selected": "Bool? — for list items, tabs",
  "expanded": "Bool? — for disclosure triangles, tree items",
  "children": ["[AXNode] — child elements (recursive)"]
}
```

**Implementation:**
1. Resolve app name → PID via `NSWorkspace`
2. `AXUIElementCreateApplication(pid)`
3. `AXUIElementSetMessagingTimeout(element, 5.0)`
4. Recursive traversal via `kAXChildrenAttribute` up to `max_depth`
5. At each node, read: role, title, value, identifier, description, roleDescription, position, size, actions, enabled, focused, selected, expanded
6. Serialize to JSON

**Optimizations:**
- Skip empty/null fields in output to reduce token usage
- Depth limit prevents explosion on complex apps (Chrome can have thousands of nodes)
- `max_children` caps siblings per node (truncated with `"...truncated (N more)"`)
- `filter` prunes irrelevant subtrees — only returns paths to matching elements + their immediate children
- Per-element AX timeout of 2 seconds (responsive apps answer in < 50ms); overall operation timeout of 10 seconds

---

### 3.4 `click_element`

Finds a UI element by semantic search and clicks it via the Accessibility API.

**Input:**
| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `app_name` | String | Yes | — | Target app name |
| `search` | String | Yes | — | Text to search for (title, identifier, or description) |
| `role` | String | No | — | Filter by AX role (e.g., "AXButton") |
| `index` | Int | No | 0 | Which match to click (0-indexed) if multiple matches |

**Output:**
```json
{
  "success": true,
  "clicked": {
    "role": "AXStaticText",
    "title": "Good music"
  },
  "matchCount": 1
}
```

**Search strategy (priority order):**
1. Exact title match
2. Exact identifier match
3. Exact description match
4. Case-insensitive substring on title
5. Case-insensitive substring on description

If `role` is specified, only elements matching that role are considered.

**Action execution:**
1. First, `AXRaise` on the app's window to bring it to front
2. Then, `AXPress` on the found element
3. If `AXPress` is not available, fall back to `AXConfirm` or `AXPick`

**Error cases:**
- App not found → MCP error with available apps list
- Element not found → MCP error with suggestion to use `get_ax_tree` first
- Multiple matches → returns match list, clicks the one at `index`
- Permission denied → MCP error with setup instructions

---

### 3.5 `type_text`

Types text into the currently focused element.

**Input:**
| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `text` | String | Yes | — | Text to type |
| `app_name` | String | No | — | Optional: bring this app to front first |
| `element_search` | String | No | — | Optional: find and focus this element before typing (same search semantics as click_element) |

**Output:**
```json
{
  "success": true,
  "typed": "Hello world",
  "targetApp": "Notes"
}
```

**Implementation:**
1. If `app_name` given, activate that app and wait briefly
2. If `element_search` given, find the element in the AX tree, set `kAXFocusedAttribute` on it
3. Hybrid approach: first try `AXUIElementSetAttributeValue(element, kAXValueAttribute, text)` for speed; if that fails (Electron apps, web inputs), fall back to `CGEvent` keystroke simulation using `keyboardSetUnicodeString` for multi-character bursts (not character-by-character)

---

### 3.6 `press_key`

Sends keyboard shortcuts and special keys.

**Input:**
| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `key` | String | Yes | — | Key name: "return", "escape", "tab", "space", "delete", "up", "down", "left", "right", "f1"–"f12", or a single character |
| `modifiers` | [String] | No | [] | Modifier keys: "command", "shift", "option", "control" |
| `app_name` | String | No | — | Optional: bring this app to front first |

**Output:**
```json
{
  "success": true,
  "key": "c",
  "modifiers": ["command"],
  "targetApp": "Finder"
}
```

**Implementation:**
1. If `app_name` given, activate that app
2. Map key name → CGKeyCode (lookup table for named keys, CGEvent character mapping for letters)
3. Build `CGEventFlags` from modifiers array
4. Create and post CGEvent key-down + key-up pair

**Common use cases:**
- `press_key(key: "c", modifiers: ["command"])` → Copy
- `press_key(key: "v", modifiers: ["command"])` → Paste
- `press_key(key: "return")` → Submit/Confirm
- `press_key(key: "escape")` → Cancel/Close
- `press_key(key: "tab")` → Next field
- `press_key(key: "a", modifiers: ["command"])` → Select All

---

## 4. Error Handling

All errors are returned as structured MCP error responses:

| Error Code | Condition | Message |
|---|---|---|
| `PERMISSION_DENIED` | AX access not granted | "Accessibility permission required. Open System Settings → Privacy & Security → Accessibility and grant permission to ai-os-mcp." |
| `APP_NOT_FOUND` | App name doesn't match any running app | "App '{name}' not found. Running apps: [list]" |
| `ELEMENT_NOT_FOUND` | Search matched nothing | "No element matching '{search}' found. Use get_ax_tree to inspect available elements." |
| `APP_NOT_RESPONDING` | AX call timed out (5s) | "App '{name}' is not responding to accessibility queries." |
| `ACTION_FAILED` | AXPerformAction returned error | "Failed to perform {action} on element: {AXError description}" |

---

## 5. Project Structure

```
ai-os-mcp/
├── Package.swift
├── LICENSE                        # MIT
├── README.md
├── CONTRIBUTING.md
├── .github/
│   └── workflows/
│       └── build.yml              # CI: build + lint on macOS
├── Sources/
│   └── ai-os-mcp/
│       ├── main.swift             # Entry point: permission check, server init, stdio transport
│       ├── Server.swift           # MCP server setup: tool registration, request routing
│       ├── Tools/
│       │   ├── GetRunningApps.swift
│       │   ├── GetFrontmostApp.swift
│       │   ├── GetAXTree.swift
│       │   ├── ClickElement.swift
│       │   ├── TypeText.swift
│       │   └── PressKey.swift
│       ├── AX/
│       │   ├── AXTreeReader.swift # Recursive tree traversal, JSON serialization
│       │   ├── AXElementSearch.swift  # Element search by title/id/description
│       │   ├── AXActions.swift    # Press, type, raise — action execution
│       │   └── AXHelpers.swift    # getAttribute, getActions, error mapping
│       ├── App/
│       │   └── AppResolver.swift  # NSWorkspace app lookup, PID resolution
│       └── Models/
│           ├── AXNode.swift       # AX node struct + Codable
│           ├── AppInfo.swift      # App info struct + Codable
│           └── Errors.swift       # Typed error definitions
├── Tests/
│   └── ai-os-mcpTests/
│       ├── AppResolverTests.swift
│       ├── AXTreeReaderTests.swift
│       └── AXElementSearchTests.swift
├── scripts/
│   └── install.sh                 # Build release + configure Claude Desktop
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-03-14-ai-os-mcp-design.md
```

---

## 6. Installation & Setup

### Build from source
```bash
git clone https://github.com/charantejmandali18/ai-os-mcp.git
cd ai-os-mcp
swift build -c release
```

### Install for Claude Desktop
```bash
./scripts/install.sh
```

This script:
1. Builds the release binary
2. Copies it to `~/.local/bin/ai-os-mcp`
3. Adds the MCP server config to `~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "ai-os-mcp": {
      "command": "/Users/<username>/.local/bin/ai-os-mcp"
    }
  }
}
```
4. Prompts user to grant Accessibility permission if not already granted

### Grant Accessibility Permission
1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the `+` button
3. Navigate to `~/.local/bin/ai-os-mcp` and add it
4. Toggle it ON
5. Restart Claude Desktop

---

## 7. CI/CD

GitHub Actions workflow on macOS runner:

- **Trigger:** Push to `main`, PRs
- **Steps:** Swift build, swift test, swiftlint
- **Artifact:** Release binary for macOS (arm64 + x86_64 universal)
- **Releases:** Tagged releases with pre-built binary attached

---

## 8. Success Criteria

Phase 0 is complete when:

1. `get_running_apps` returns all GUI apps with correct metadata
2. `get_frontmost_app` correctly identifies the active app
3. `get_ax_tree("Spotify")` returns the full sidebar, player controls, and playlists as structured JSON
4. `click_element("Spotify", "Good music")` successfully plays the playlist — zero coordinate math
5. `type_text("hello", app_name: "Notes")` types into Apple Notes
6. `press_key(key: "c", modifiers: ["command"])` copies selected text
7. All of the above work from Claude Desktop via MCP with < 200ms latency for tree reads
7. Clean installation experience documented in README
8. CI passing on GitHub

---

## 9. Future Extensions (Not in Phase 0)

- `scroll_element` — scroll within a scroll area
- `get_element_at_position` — reverse lookup from screen coordinates
- `watch_element` — subscribe to AX notifications for element changes
- `drag_element` — drag and drop support
- Caching layer for repeated tree reads
- WebSocket transport for remote access
