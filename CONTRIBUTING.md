# Contributing to ai-os-mcp

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 16.0+ (includes Swift 6.0)
- Accessibility permission granted in System Settings

### Build

```bash
git clone https://github.com/charantejmandali18/ai-os-mcp.git
cd ai-os-mcp
swift build
```

### Test

```bash
swift test
```

> **Note:** Some tests require Accessibility permission to be granted to the test runner. If tests fail with permission errors, open System Settings > Privacy & Security > Accessibility and add your terminal or Xcode.

### Run locally

```bash
swift build -c release
.build/release/ai-os-mcp
```

The server communicates over stdin/stdout (MCP protocol). You'll see startup logs on stderr.

## Code Style

- Follow standard Swift conventions
- Use Swift 6 strict concurrency where applicable
- Keep files focused — one responsibility per file
- Prefer descriptive names over comments

## Pull Requests

1. Fork the repo and create a feature branch from `main`
2. Make your changes with clear, atomic commits
3. Ensure `swift build` succeeds with no warnings
4. Ensure `swift test` passes
5. Open a PR with a clear description of what and why

## Reporting Issues

Open a GitHub issue with:

- macOS version
- Swift version (`swift --version`)
- Steps to reproduce
- Expected vs actual behavior
- Any error output

## Architecture Overview

```
Sources/ai-os-mcp/
├── main.swift          # Entry point
├── Server.swift        # MCP tool registration and routing
├── Tools/              # One file per MCP tool handler
├── AX/                 # Accessibility API wrappers
├── App/                # App discovery (NSWorkspace)
└── Models/             # Data types (AXNode, AppInfo, Errors)
```

The key principle: **MCP tool handlers are thin** — they parse arguments, call into the AX layer, and format responses. The AX layer does all the heavy lifting.
