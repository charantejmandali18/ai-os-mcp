# AI-OS MCP Server Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native Swift MCP server that exposes macOS Accessibility API as tools for AI assistants — enabling semantic UI control without screenshots or coordinate math.

**Architecture:** Single Swift executable communicating over stdio (JSON-RPC) using the official `modelcontextprotocol/swift-sdk`. AX operations dispatched to a dedicated serial queue to avoid blocking the async MCP event loop. Non-sandboxed for cross-process accessibility access.

**Tech Stack:** Swift 6.0+, MCP Swift SDK 0.11.0, ApplicationServices.framework, AppKit, CoreGraphics, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-03-14-ai-os-mcp-design.md`

---

## File Structure

```
ai-os-mcp/
├── Package.swift                          # SPM manifest
├── Sources/
│   └── ai-os-mcp/
│       ├── main.swift                     # Entry point: permission check, server bootstrap
│       ├── Server.swift                   # MCP tool registration, CallTool dispatch
│       ├── Tools/
│       │   ├── GetRunningApps.swift       # List GUI apps
│       │   ├── GetFrontmostApp.swift      # Active app info
│       │   ├── GetAXTree.swift            # AX tree read with filtering
│       │   ├── ClickElement.swift         # Semantic element click
│       │   ├── TypeText.swift             # Text input (hybrid AXValue/CGEvent)
│       │   └── PressKey.swift             # Keyboard shortcuts via CGEvent
│       ├── AX/
│       │   ├── AXTreeReader.swift         # Recursive tree traversal
│       │   ├── AXElementSearch.swift      # Element search by title/id/desc
│       │   ├── AXActions.swift            # Press, raise, focus actions
│       │   └── AXHelpers.swift            # getAttribute, getActions, error mapping
│       ├── App/
│       │   └── AppResolver.swift          # NSWorkspace app lookup, PID resolution
│       └── Models/
│           ├── AXNode.swift               # AX node Codable struct
│           ├── AppInfo.swift              # App info Codable struct
│           └── Errors.swift               # Typed error definitions
├── Tests/
│   └── ai-os-mcpTests/
│       ├── AppResolverTests.swift
│       ├── AXNodeTests.swift
│       └── KeyMappingTests.swift
├── scripts/
│   └── install.sh                         # Build + configure Claude Desktop
├── .github/
│   └── workflows/
│       └── build.yml                      # CI: build on macOS
├── .gitignore
├── LICENSE
├── CONTRIBUTING.md
└── README.md
```

---

## Chunk 1: Project Foundation + Models

### Task 1: Initialize Swift Package

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ai-os-mcp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .executableTarget(
            name: "ai-os-mcp",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "ai-os-mcpTests",
            dependencies: ["ai-os-mcp"]
        ),
    ]
)
```

- [ ] **Step 2: Create .gitignore**

```
.DS_Store
/.build
/Packages
xcuserdata/
DerivedData/
.swiftpm/
Package.resolved
```

- [ ] **Step 3: Create minimal main.swift to verify build**

File: `Sources/ai-os-mcp/main.swift`

```swift
import Foundation

print("ai-os-mcp starting...", to: &standardError)
```

We need a stderr helper since MCP uses stdout for JSON-RPC:

```swift
var standardError = FileHandle.standardError

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}
```

- [ ] **Step 4: Resolve dependencies and build**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Init git repo and commit**

```bash
cd /Users/charantej/charan_personal_projects/ai-os-mcp
git init
git add Package.swift .gitignore Sources/ai-os-mcp/main.swift
git commit -m "chore: initialize Swift package with MCP SDK dependency"
```

---

### Task 2: Define Error Types

**Files:**
- Create: `Sources/ai-os-mcp/Models/Errors.swift`

- [ ] **Step 1: Create Errors.swift**

```swift
import Foundation

enum AIOSError: Error, CustomStringConvertible {
    case permissionDenied
    case appNotFound(name: String, available: [String])
    case elementNotFound(search: String)
    case appNotResponding(name: String)
    case actionFailed(action: String, detail: String)
    case invalidArguments(detail: String)

    var description: String {
        switch self {
        case .permissionDenied:
            return "Accessibility permission required. Open System Settings → Privacy & Security → Accessibility and grant permission to ai-os-mcp."
        case .appNotFound(let name, let available):
            return "App '\(name)' not found. Running apps: \(available.joined(separator: ", "))"
        case .elementNotFound(let search):
            return "No element matching '\(search)' found. Use get_ax_tree to inspect available elements."
        case .appNotResponding(let name):
            return "App '\(name)' is not responding to accessibility queries."
        case .actionFailed(let action, let detail):
            return "Failed to perform \(action): \(detail)"
        case .invalidArguments(let detail):
            return "Invalid arguments: \(detail)"
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/ai-os-mcp/Models/Errors.swift
git commit -m "feat: add typed error definitions"
```

---

### Task 3: Define AppInfo Model

**Files:**
- Create: `Sources/ai-os-mcp/Models/AppInfo.swift`

- [ ] **Step 1: Create AppInfo.swift**

```swift
import Foundation

struct AppInfo: Codable, Sendable {
    let name: String
    let pid: Int32
    let bundleId: String?
    let isActive: Bool
}
```

- [ ] **Step 2: Build and commit**

Run: `swift build`

```bash
git add Sources/ai-os-mcp/Models/AppInfo.swift
git commit -m "feat: add AppInfo model"
```

---

### Task 4: Define AXNode Model

**Files:**
- Create: `Sources/ai-os-mcp/Models/AXNode.swift`

- [ ] **Step 1: Create AXNode.swift**

```swift
import Foundation

struct AXNode: Codable, Sendable {
    let role: String
    var title: String?
    var value: AXNodeValue?
    var identifier: String?
    var description: String?
    var roleDescription: String?
    var position: AXPoint?
    var size: AXSize?
    var actions: [String]?
    var enabled: Bool?
    var focused: Bool?
    var selected: Bool?
    var expanded: Bool?
    var children: [AXNode]?

    struct AXPoint: Codable, Sendable {
        let x: Double
        let y: Double
    }

    struct AXSize: Codable, Sendable {
        let width: Double
        let height: Double
    }
}

/// Wrapper to handle heterogeneous AX values in JSON
enum AXNodeValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else {
            self = .string("")
        }
    }
}

/// Custom JSON encoder that skips nil fields
extension AXNode {
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
```

- [ ] **Step 2: Write AXNode serialization test**

File: `Tests/ai-os-mcpTests/AXNodeTests.swift`

```swift
import Testing
@testable import ai_os_mcp

@Test func testAXNodeSerializationSkipsNils() throws {
    let node = AXNode(
        role: "AXButton",
        title: "Play",
        actions: ["AXPress"],
        enabled: true
    )
    let json = try node.toJSON()
    #expect(json.contains("\"role\":\"AXButton\""))
    #expect(json.contains("\"title\":\"Play\""))
    #expect(!json.contains("\"identifier\""))
    #expect(!json.contains("\"position\""))
}

@Test func testAXNodeValueEncoding() throws {
    let encoder = JSONEncoder()

    let strVal = AXNodeValue.string("hello")
    let strData = try encoder.encode(strVal)
    #expect(String(data: strData, encoding: .utf8) == "\"hello\"")

    let numVal = AXNodeValue.number(42.0)
    let numData = try encoder.encode(numVal)
    #expect(String(data: numData, encoding: .utf8) == "42")

    let boolVal = AXNodeValue.bool(true)
    let boolData = try encoder.encode(boolVal)
    #expect(String(data: boolData, encoding: .utf8) == "true")
}
```

- [ ] **Step 3: Run tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/ai-os-mcp/Models/AXNode.swift Tests/ai-os-mcpTests/AXNodeTests.swift
git commit -m "feat: add AXNode model with Codable serialization"
```

---

## Chunk 2: App Resolver + AX Helpers

### Task 5: Implement AppResolver

**Files:**
- Create: `Sources/ai-os-mcp/App/AppResolver.swift`
- Create: `Tests/ai-os-mcpTests/AppResolverTests.swift`

- [ ] **Step 1: Create AppResolver.swift**

```swift
import AppKit
import Foundation

final class AppResolver: Sendable {
    /// List all GUI (regular activation policy) running apps
    func listRunningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let name = app.localizedName else { return nil }
                return AppInfo(
                    name: name,
                    pid: app.processIdentifier,
                    bundleId: app.bundleIdentifier,
                    isActive: app.isActive
                )
            }
    }

    /// Get the frontmost (active) app
    func frontmostApp() -> AppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let name = app.localizedName else { return nil }
        return AppInfo(
            name: name,
            pid: app.processIdentifier,
            bundleId: app.bundleIdentifier,
            isActive: true
        )
    }

    /// Resolve an app name to a PID. Case-insensitive, partial match.
    /// Prefers the frontmost app if multiple match.
    func resolve(appName: String) throws -> (pid: pid_t, name: String) {
        let query = appName.lowercased()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var matches: [(pid: pid_t, name: String, isActive: Bool)] = []

        for app in apps {
            guard let name = app.localizedName else { continue }
            if name.lowercased() == query || name.lowercased().contains(query) {
                matches.append((app.processIdentifier, name, app.isActive))
            }
        }

        if matches.isEmpty {
            let available = apps.compactMap { $0.localizedName }
            throw AIOSError.appNotFound(name: appName, available: available)
        }

        // Prefer exact match, then frontmost, then first
        if let exact = matches.first(where: { $0.name.lowercased() == query }) {
            return (exact.pid, exact.name)
        }
        if let active = matches.first(where: { $0.isActive }) {
            return (active.pid, active.name)
        }
        return (matches[0].pid, matches[0].name)
    }
}
```

- [ ] **Step 2: Write AppResolver tests**

```swift
import Testing
@testable import ai_os_mcp

@Test func testListRunningAppsReturnsNonEmpty() {
    let resolver = AppResolver()
    let apps = resolver.listRunningApps()
    #expect(!apps.isEmpty, "Should have at least one running GUI app")
}

@Test func testFrontmostAppReturnsValue() {
    let resolver = AppResolver()
    let app = resolver.frontmostApp()
    #expect(app != nil, "Should have a frontmost app")
}

@Test func testResolveFinderByName() throws {
    let resolver = AppResolver()
    // Finder is always running on macOS
    let (pid, name) = try resolver.resolve(appName: "Finder")
    #expect(pid > 0)
    #expect(name == "Finder")
}

@Test func testResolveCaseInsensitive() throws {
    let resolver = AppResolver()
    let (pid, _) = try resolver.resolve(appName: "finder")
    #expect(pid > 0)
}

@Test func testResolveUnknownAppThrows() {
    let resolver = AppResolver()
    #expect(throws: AIOSError.self) {
        try resolver.resolve(appName: "NonExistentApp12345")
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/ai-os-mcp/App/AppResolver.swift Tests/ai-os-mcpTests/AppResolverTests.swift
git commit -m "feat: add AppResolver with name-to-PID resolution"
```

---

### Task 6: Implement AX Helpers

**Files:**
- Create: `Sources/ai-os-mcp/AX/AXHelpers.swift`

- [ ] **Step 1: Create AXHelpers.swift**

```swift
import ApplicationServices
import Foundation

// MARK: - Attribute Reading

func axGetAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return result == .success ? value : nil
}

func axGetStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    axGetAttribute(element, attribute) as? String
}

func axGetBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
    axGetAttribute(element, attribute) as? Bool
}

func axGetChildren(_ element: AXUIElement) -> [AXUIElement] {
    (axGetAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func axGetActions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    let result = AXUIElementCopyActionNames(element, &names)
    return result == .success ? (names as? [String] ?? []) : []
}

func axGetPosition(_ element: AXUIElement) -> AXNode.AXPoint? {
    guard let value = axGetAttribute(element, kAXPositionAttribute) else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return AXNode.AXPoint(x: Double(point.x), y: Double(point.y))
}

func axGetSize(_ element: AXUIElement) -> AXNode.AXSize? {
    guard let value = axGetAttribute(element, kAXSizeAttribute) else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return AXNode.AXSize(width: Double(size.width), height: Double(size.height))
}

// MARK: - Value Conversion

func axConvertValue(_ raw: CFTypeRef) -> AXNodeValue? {
    if let s = raw as? String { return .string(s) }
    if let n = raw as? NSNumber {
        // NSNumber wraps both bools and numbers — check CFBoolean first
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .bool(n.boolValue)
        }
        return .number(n.doubleValue)
    }
    // For other types, stringify
    let desc = "\(raw)"
    if !desc.isEmpty && desc != "<AXUIElement>" {
        return .string(desc)
    }
    return nil
}

// MARK: - Permission Check

func axCheckPermission() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// MARK: - Error Description

func axErrorDescription(_ error: AXError) -> String {
    switch error {
    case .success: return "success"
    case .failure: return "generic failure"
    case .illegalArgument: return "illegal argument"
    case .invalidUIElement: return "invalid UI element (stale reference)"
    case .invalidUIElementObserver: return "invalid observer"
    case .cannotComplete: return "cannot complete (app may be unresponsive)"
    case .attributeUnsupported: return "attribute unsupported"
    case .actionUnsupported: return "action unsupported"
    case .notificationUnsupported: return "notification unsupported"
    case .notImplemented: return "not implemented"
    case .notificationAlreadyRegistered: return "notification already registered"
    case .notificationNotRegistered: return "notification not registered"
    case .apiDisabled: return "accessibility API disabled"
    case .noValue: return "no value"
    case .parameterizedAttributeUnsupported: return "parameterized attribute unsupported"
    case .notEnoughPrecision: return "not enough precision"
    @unknown default: return "unknown error (\(error.rawValue))"
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/ai-os-mcp/AX/AXHelpers.swift
git commit -m "feat: add AX helper functions for attribute reading and value conversion"
```

---

## Chunk 3: AX Tree Reader + Element Search

### Task 7: Implement AXTreeReader

**Files:**
- Create: `Sources/ai-os-mcp/AX/AXTreeReader.swift`

- [ ] **Step 1: Create AXTreeReader.swift**

```swift
import ApplicationServices
import Foundation

final class AXTreeReader: Sendable {
    /// Read the AX tree for an application PID.
    /// - Parameters:
    ///   - pid: Process ID of the target app
    ///   - maxDepth: Maximum recursion depth (default 5)
    ///   - maxChildren: Max children per node (default 50)
    ///   - filter: Optional text filter — only return subtrees containing matches
    func readTree(
        pid: pid_t,
        maxDepth: Int = 5,
        maxChildren: Int = 50,
        filter: String? = nil
    ) -> AXNode? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 2.0)

        if let filter = filter, !filter.isEmpty {
            return readNodeFiltered(appElement, depth: 0, maxDepth: maxDepth + 3, maxChildren: maxChildren, filter: filter.lowercased())
        } else {
            return readNode(appElement, depth: 0, maxDepth: maxDepth, maxChildren: maxChildren)
        }
    }

    /// Standard recursive tree read
    private func readNode(_ element: AXUIElement, depth: Int, maxDepth: Int, maxChildren: Int) -> AXNode? {
        guard depth <= maxDepth else { return nil }

        let role = axGetStringAttribute(element, kAXRoleAttribute) ?? "Unknown"
        var node = buildNode(element, role: role)

        if depth < maxDepth {
            let allChildren = axGetChildren(element)
            let truncated = allChildren.count > maxChildren
            let childSlice = allChildren.prefix(maxChildren)

            var childNodes: [AXNode] = []
            for child in childSlice {
                if let childNode = readNode(child, depth: depth + 1, maxDepth: maxDepth, maxChildren: maxChildren) {
                    childNodes.append(childNode)
                }
            }

            if truncated {
                var placeholder = AXNode(role: "Truncated")
                placeholder.title = "... \(allChildren.count - maxChildren) more children"
                childNodes.append(placeholder)
            }

            if !childNodes.isEmpty {
                node.children = childNodes
            }
        }

        return node
    }

    /// Filtered tree read — only returns paths to matching elements
    private func readNodeFiltered(_ element: AXUIElement, depth: Int, maxDepth: Int, maxChildren: Int, filter: String) -> AXNode? {
        guard depth <= maxDepth else { return nil }

        let role = axGetStringAttribute(element, kAXRoleAttribute) ?? "Unknown"
        let node = buildNode(element, role: role)
        let matches = nodeMatchesFilter(node, filter: filter)

        let allChildren = axGetChildren(element)
        let childSlice = allChildren.prefix(maxChildren)

        var matchingChildren: [AXNode] = []
        for child in childSlice {
            if let childNode = readNodeFiltered(child, depth: depth + 1, maxDepth: maxDepth, maxChildren: maxChildren, filter: filter) {
                matchingChildren.append(childNode)
            }
        }

        if matches || !matchingChildren.isEmpty {
            var result = node
            if !matchingChildren.isEmpty {
                result.children = matchingChildren
            }
            return result
        }

        return nil
    }

    private func nodeMatchesFilter(_ node: AXNode, filter: String) -> Bool {
        if let t = node.title, t.lowercased().contains(filter) { return true }
        if let id = node.identifier, id.lowercased().contains(filter) { return true }
        if let d = node.description, d.lowercased().contains(filter) { return true }
        return false
    }

    private func buildNode(_ element: AXUIElement, role: String) -> AXNode {
        let title = axGetStringAttribute(element, kAXTitleAttribute)
        let rawValue = axGetAttribute(element, kAXValueAttribute)
        let value = rawValue.flatMap { axConvertValue($0) }
        let identifier = axGetStringAttribute(element, kAXIdentifierAttribute)
        let desc = axGetStringAttribute(element, kAXDescriptionAttribute)
        let roleDesc = axGetStringAttribute(element, kAXRoleDescriptionAttribute)
        let position = axGetPosition(element)
        let size = axGetSize(element)
        let actions = axGetActions(element)
        let enabled = axGetBoolAttribute(element, kAXEnabledAttribute)
        let focused = axGetBoolAttribute(element, kAXFocusedAttribute)
        let selected = axGetBoolAttribute(element, kAXSelectedAttribute)
        let expanded = axGetBoolAttribute(element, kAXExpandedAttribute)

        return AXNode(
            role: role,
            title: title,
            value: value,
            identifier: identifier,
            description: desc,
            roleDescription: roleDesc,
            position: position,
            size: size,
            actions: actions?.isEmpty == true ? nil : actions,
            enabled: enabled,
            focused: focused,
            selected: selected,
            expanded: expanded
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/ai-os-mcp/AX/AXTreeReader.swift
git commit -m "feat: add AXTreeReader with depth limiting and filter support"
```

---

### Task 8: Implement AXElementSearch

**Files:**
- Create: `Sources/ai-os-mcp/AX/AXElementSearch.swift`

- [ ] **Step 1: Create AXElementSearch.swift**

```swift
import ApplicationServices
import Foundation

struct AXSearchResult: Sendable {
    let element: AXUIElement
    let role: String
    let title: String?
    let identifier: String?
    let description: String?
}

final class AXElementSearch: Sendable {

    /// Search the AX tree for elements matching the query.
    /// Priority: exact title > exact id > exact desc > substring title > substring desc
    /// Optionally filter by role.
    func search(
        root: AXUIElement,
        query: String,
        role: String? = nil,
        maxResults: Int = 20
    ) -> [AXSearchResult] {
        var exactTitle: [AXSearchResult] = []
        var exactId: [AXSearchResult] = []
        var exactDesc: [AXSearchResult] = []
        var substringTitle: [AXSearchResult] = []
        var substringDesc: [AXSearchResult] = []

        let lowerQuery = query.lowercased()

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 15 else { return }

            let r = axGetStringAttribute(element, kAXRoleAttribute) ?? ""

            if let role = role, r != role {
                // Still recurse into children even if this element's role doesn't match
            } else {
                let t = axGetStringAttribute(element, kAXTitleAttribute)
                let id = axGetStringAttribute(element, kAXIdentifierAttribute)
                let d = axGetStringAttribute(element, kAXDescriptionAttribute)

                let result = AXSearchResult(element: element, role: r, title: t, identifier: id, description: d)

                if let t = t, t == query { exactTitle.append(result) }
                else if let id = id, id == query { exactId.append(result) }
                else if let d = d, d == query { exactDesc.append(result) }
                else if let t = t, t.lowercased().contains(lowerQuery) { substringTitle.append(result) }
                else if let d = d, d.lowercased().contains(lowerQuery) { substringDesc.append(result) }
            }

            // Always recurse — role filter only affects match, not traversal
            let children = axGetChildren(element)
            for child in children {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)

        // Combine in priority order
        var results: [AXSearchResult] = []
        results.append(contentsOf: exactTitle)
        results.append(contentsOf: exactId)
        results.append(contentsOf: exactDesc)
        results.append(contentsOf: substringTitle)
        results.append(contentsOf: substringDesc)

        return Array(results.prefix(maxResults))
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/ai-os-mcp/AX/AXElementSearch.swift
git commit -m "feat: add AXElementSearch with priority-based matching"
```

---

### Task 9: Implement AXActions

**Files:**
- Create: `Sources/ai-os-mcp/AX/AXActions.swift`

- [ ] **Step 1: Create AXActions.swift**

```swift
import ApplicationServices
import AppKit
import Foundation

final class AXActions: Sendable {

    /// Bring an app's window to front
    func raiseApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    /// Press (click) an AX element
    func pressElement(_ element: AXUIElement) throws {
        let actions = axGetActions(element)

        if actions.contains(kAXPressAction as String) {
            let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
            if result != .success {
                throw AIOSError.actionFailed(action: "AXPress", detail: axErrorDescription(result))
            }
        } else if actions.contains(kAXConfirmAction as String) {
            let result = AXUIElementPerformAction(element, kAXConfirmAction as CFString)
            if result != .success {
                throw AIOSError.actionFailed(action: "AXConfirm", detail: axErrorDescription(result))
            }
        } else if actions.contains(kAXPickAction as String) {
            let result = AXUIElementPerformAction(element, kAXPickAction as CFString)
            if result != .success {
                throw AIOSError.actionFailed(action: "AXPick", detail: axErrorDescription(result))
            }
        } else {
            throw AIOSError.actionFailed(action: "press", detail: "Element has no press/confirm/pick action. Available: \(actions)")
        }
    }

    /// Focus an AX element
    func focusElement(_ element: AXUIElement) {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
    }

    /// Try setting a text value directly on an AX element.
    /// Returns true if successful, false if the element doesn't support it.
    func setTextValue(_ element: AXUIElement, text: String) -> Bool {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        return result == .success
    }

    /// Type text using CGEvent keystroke simulation.
    /// Uses keyboardSetUnicodeString for efficiency.
    func typeTextViaCGEvent(_ text: String) {
        // Process in chunks for efficiency
        let chunkSize = 20
        let chars = Array(text.utf16)

        for i in stride(from: 0, to: chars.count, by: chunkSize) {
            let end = min(i + chunkSize, chars.count)
            let chunk = Array(chars[i..<end])

            if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
                // Small delay between chunks to let the app process
                usleep(10_000) // 10ms
            }
        }
    }

    // MARK: - Key Press

    /// Press a key with optional modifiers using CGEvent
    func pressKey(key: String, modifiers: [String]) throws {
        guard let keyCode = keyCodeFor(key) else {
            throw AIOSError.invalidArguments(detail: "Unknown key: '\(key)'. Valid keys: return, escape, tab, space, delete, up, down, left, right, f1-f12, or a single character.")
        }

        var flags = CGEventFlags()
        for mod in modifiers {
            switch mod.lowercased() {
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            default:
                throw AIOSError.invalidArguments(detail: "Unknown modifier: '\(mod)'. Valid: command, shift, option, control")
            }
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw AIOSError.actionFailed(action: "press_key", detail: "Failed to create CGEvent")
        }

        // If it's a single character key, set the unicode string
        if key.count == 1, keyCode == 0 {
            let utf16 = Array(key.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Key Code Mapping

    private func keyCodeFor(_ key: String) -> CGKeyCode? {
        // Named keys
        let namedKeys: [String: CGKeyCode] = [
            "return": 0x24, "enter": 0x24,
            "tab": 0x30,
            "space": 0x31,
            "delete": 0x33, "backspace": 0x33,
            "escape": 0x35, "esc": 0x35,
            "left": 0x7B,
            "right": 0x7C,
            "down": 0x7D,
            "up": 0x7E,
            "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
            "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
            "home": 0x73, "end": 0x77,
            "pageup": 0x74, "pagedown": 0x79,
            "forwarddelete": 0x75,
        ]

        let lower = key.lowercased()
        if let code = namedKeys[lower] {
            return code
        }

        // Single character — map common letters/numbers
        if key.count == 1 {
            let charMap: [Character: CGKeyCode] = [
                "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03,
                "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
                "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
                "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
                "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
                "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
                "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C,
                "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
                "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25,
                "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
                "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D,
                "m": 0x2E, ".": 0x2F, "`": 0x32,
            ]

            if let code = charMap[Character(lower)] {
                return code
            }

            // Fallback: use keyCode 0 with unicode string (handled in pressKey)
            return 0
        }

        return nil
    }
}
```

- [ ] **Step 2: Write key mapping test**

File: `Tests/ai-os-mcpTests/KeyMappingTests.swift`

```swift
import Testing
@testable import ai_os_mcp

@Test func testPressKeyRejectsUnknownKey() {
    let actions = AXActions()
    #expect(throws: AIOSError.self) {
        try actions.pressKey(key: "unknownkey", modifiers: [])
    }
}

@Test func testPressKeyRejectsUnknownModifier() {
    let actions = AXActions()
    #expect(throws: AIOSError.self) {
        try actions.pressKey(key: "a", modifiers: ["superkey"])
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/ai-os-mcp/AX/AXActions.swift Tests/ai-os-mcpTests/KeyMappingTests.swift
git commit -m "feat: add AXActions with press, focus, type, and key press support"
```

---

## Chunk 3: MCP Server + Tool Handlers

### Task 10: Implement Tool Definitions (Server.swift)

**Files:**
- Create: `Sources/ai-os-mcp/Server.swift`

- [ ] **Step 1: Create Server.swift with tool registration**

```swift
import Foundation
import MCP

/// Registers all MCP tools and routes CallTool requests to handlers.
func registerTools(on server: Server) async {
    let appResolver = AppResolver()
    let treeReader = AXTreeReader()
    let elementSearch = AXElementSearch()
    let axActions = AXActions()

    // MARK: - List Tools

    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: [
            Tool(
                name: "get_running_apps",
                description: "List all running GUI applications with their names, PIDs, and bundle IDs.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ])
            ),
            Tool(
                name: "get_frontmost_app",
                description: "Get the currently focused (frontmost) application.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ])
            ),
            Tool(
                name: "get_ax_tree",
                description: "Read the semantic UI tree (accessibility tree) of a running application. Returns a structured JSON tree of every UI element — buttons, text fields, labels, lists, etc. Use this to understand what's on screen before taking actions.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Application name (case-insensitive, partial match)")
                        ]),
                        "max_depth": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum tree depth (default: 5)")
                        ]),
                        "max_children": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum children per node (default: 50)")
                        ]),
                        "filter": .object([
                            "type": .string("string"),
                            "description": .string("Only return subtrees containing elements matching this text")
                        ]),
                    ]),
                    "required": .array([.string("app_name")]),
                ])
            ),
            Tool(
                name: "click_element",
                description: "Find a UI element by its title, identifier, or description and click it. No coordinate math — finds the element semantically in the accessibility tree and performs AXPress.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Target application name")
                        ]),
                        "search": .object([
                            "type": .string("string"),
                            "description": .string("Text to search for in element title, identifier, or description")
                        ]),
                        "role": .object([
                            "type": .string("string"),
                            "description": .string("Optional AX role filter (e.g., AXButton, AXMenuItem)")
                        ]),
                        "index": .object([
                            "type": .string("integer"),
                            "description": .string("Which match to click if multiple found (0-indexed, default: 0)")
                        ]),
                    ]),
                    "required": .array([.string("app_name"), .string("search")]),
                ])
            ),
            Tool(
                name: "type_text",
                description: "Type text into the currently focused element, or into a specific element found by search. Uses the fastest available method (direct value setting, falling back to keystroke simulation).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("Text to type")
                        ]),
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Optional: bring this app to front first")
                        ]),
                        "element_search": .object([
                            "type": .string("string"),
                            "description": .string("Optional: find and focus this element before typing")
                        ]),
                    ]),
                    "required": .array([.string("text")]),
                ])
            ),
            Tool(
                name: "press_key",
                description: "Send a keyboard shortcut or special key press. Supports modifier keys (command, shift, option, control) and named keys (return, escape, tab, arrows, F-keys).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "key": .object([
                            "type": .string("string"),
                            "description": .string("Key name: return, escape, tab, space, delete, up, down, left, right, f1-f12, or a single character")
                        ]),
                        "modifiers": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Modifier keys: command, shift, option, control")
                        ]),
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Optional: bring this app to front first")
                        ]),
                    ]),
                    "required": .array([.string("key")]),
                ])
            ),
        ])
    }

    // MARK: - Call Tool

    await server.withMethodHandler(CallTool.self) { params in
        do {
            switch params.name {
            case "get_running_apps":
                return try handleGetRunningApps(appResolver: appResolver)
            case "get_frontmost_app":
                return try handleGetFrontmostApp(appResolver: appResolver)
            case "get_ax_tree":
                return try handleGetAXTree(params: params, appResolver: appResolver, treeReader: treeReader)
            case "click_element":
                return try handleClickElement(params: params, appResolver: appResolver, search: elementSearch, actions: axActions)
            case "type_text":
                return try handleTypeText(params: params, appResolver: appResolver, search: elementSearch, actions: axActions)
            case "press_key":
                return try handlePressKey(params: params, appResolver: appResolver, actions: axActions)
            default:
                return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
            }
        } catch let error as AIOSError {
            return .init(content: [.text(text: error.description, annotations: nil, _meta: nil)], isError: true)
        } catch {
            return .init(content: [.text(text: "Internal error: \(error.localizedDescription)", annotations: nil, _meta: nil)], isError: true)
        }
    }
}
```

- [ ] **Step 2: Build** (will fail — tool handlers not yet defined — that's expected)

Run: `swift build 2>&1 | head -5`
Expected: Compile errors for missing handler functions

- [ ] **Step 3: Commit**

```bash
git add Sources/ai-os-mcp/Server.swift
git commit -m "feat: add MCP server with tool definitions and routing"
```

---

### Task 11: Implement Tool Handlers

**Files:**
- Create: `Sources/ai-os-mcp/Tools/GetRunningApps.swift`
- Create: `Sources/ai-os-mcp/Tools/GetFrontmostApp.swift`
- Create: `Sources/ai-os-mcp/Tools/GetAXTree.swift`
- Create: `Sources/ai-os-mcp/Tools/ClickElement.swift`
- Create: `Sources/ai-os-mcp/Tools/TypeText.swift`
- Create: `Sources/ai-os-mcp/Tools/PressKey.swift`

- [ ] **Step 1: Create GetRunningApps.swift**

```swift
import Foundation
import MCP

func handleGetRunningApps(appResolver: AppResolver) throws -> CallTool.Result {
    let apps = appResolver.listRunningApps()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(["apps": apps])
    let text = String(data: json, encoding: .utf8) ?? "[]"
    return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
}
```

- [ ] **Step 2: Create GetFrontmostApp.swift**

```swift
import Foundation
import MCP

func handleGetFrontmostApp(appResolver: AppResolver) throws -> CallTool.Result {
    guard let app = appResolver.frontmostApp() else {
        return .init(content: [.text(text: "No frontmost application found", annotations: nil, _meta: nil)], isError: true)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(app)
    let text = String(data: json, encoding: .utf8) ?? "{}"
    return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
}
```

- [ ] **Step 3: Create GetAXTree.swift**

```swift
import ApplicationServices
import Foundation
import MCP

func handleGetAXTree(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    treeReader: AXTreeReader
) throws -> CallTool.Result {
    guard axCheckPermission() else {
        throw AIOSError.permissionDenied
    }

    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }

    let maxDepth = params.arguments?["max_depth"]?.intValue ?? 5
    let maxChildren = params.arguments?["max_children"]?.intValue ?? 50
    let filter = params.arguments?["filter"]?.stringValue

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)

    guard let tree = treeReader.readTree(
        pid: pid,
        maxDepth: maxDepth,
        maxChildren: maxChildren,
        filter: filter
    ) else {
        throw AIOSError.appNotResponding(name: resolvedName)
    }

    struct TreeResponse: Codable {
        let app: String
        let pid: Int32
        let tree: AXNode
    }

    let response = TreeResponse(app: resolvedName, pid: pid, tree: tree)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try encoder.encode(response)
    let text = String(data: json, encoding: .utf8) ?? "{}"

    return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
}
```

- [ ] **Step 4: Create ClickElement.swift**

```swift
import ApplicationServices
import Foundation
import MCP

func handleClickElement(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    search: AXElementSearch,
    actions: AXActions
) throws -> CallTool.Result {
    guard axCheckPermission() else {
        throw AIOSError.permissionDenied
    }

    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard let query = params.arguments?["search"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "search is required")
    }

    let role = params.arguments?["role"]?.stringValue
    let index = params.arguments?["index"]?.intValue ?? 0

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 2.0)

    // Raise the app first
    actions.raiseApp(pid: pid)
    usleep(100_000) // 100ms for app to come to front

    let results = search.search(root: appElement, query: query, role: role)

    if results.isEmpty {
        throw AIOSError.elementNotFound(search: query)
    }

    guard index < results.count else {
        throw AIOSError.invalidArguments(detail: "index \(index) out of range. Found \(results.count) matches.")
    }

    let target = results[index]
    try actions.pressElement(target.element)

    struct ClickResponse: Codable {
        let success: Bool
        let clicked: ClickedElement
        let matchCount: Int

        struct ClickedElement: Codable {
            let role: String
            let title: String?
        }
    }

    let response = ClickResponse(
        success: true,
        clicked: .init(role: target.role, title: target.title),
        matchCount: results.count
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try encoder.encode(response)
    let text = String(data: json, encoding: .utf8) ?? "{}"

    return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
}
```

- [ ] **Step 5: Create TypeText.swift**

```swift
import ApplicationServices
import Foundation
import MCP

func handleTypeText(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    search: AXElementSearch,
    actions: AXActions
) throws -> CallTool.Result {
    guard let text = params.arguments?["text"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "text is required")
    }

    let appName = params.arguments?["app_name"]?.stringValue
    let elementSearchQuery = params.arguments?["element_search"]?.stringValue

    var targetAppName: String? = nil

    // Activate the app if specified
    if let appName = appName {
        let (pid, resolvedName) = try appResolver.resolve(appName: appName)
        actions.raiseApp(pid: pid)
        targetAppName = resolvedName
        usleep(200_000) // 200ms for app activation

        // If element_search is specified, find and focus the element
        if let query = elementSearchQuery {
            guard axCheckPermission() else { throw AIOSError.permissionDenied }
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 2.0)

            let results = search.search(root: appElement, query: query)
            if results.isEmpty {
                throw AIOSError.elementNotFound(search: query)
            }
            actions.focusElement(results[0].element)
            usleep(50_000) // 50ms for focus

            // Try direct value setting first
            if actions.setTextValue(results[0].element, text: text) {
                return makeTypeResponse(text: text, app: targetAppName)
            }
        }
    }

    // Fall back to CGEvent typing
    actions.typeTextViaCGEvent(text)
    return makeTypeResponse(text: text, app: targetAppName)
}

private func makeTypeResponse(text: String, app: String?) -> CallTool.Result {
    struct TypeResponse: Codable {
        let success: Bool
        let typed: String
        let targetApp: String?
    }

    let response = TypeResponse(success: true, typed: text, targetApp: app)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
}
```

- [ ] **Step 6: Create PressKey.swift**

```swift
import Foundation
import MCP

func handlePressKey(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    actions: AXActions
) throws -> CallTool.Result {
    guard let key = params.arguments?["key"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "key is required")
    }

    let modifiers: [String] = params.arguments?["modifiers"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    let appName = params.arguments?["app_name"]?.stringValue

    var targetAppName: String? = nil

    if let appName = appName {
        let (pid, resolvedName) = try appResolver.resolve(appName: appName)
        actions.raiseApp(pid: pid)
        targetAppName = resolvedName
        usleep(100_000) // 100ms
    }

    try actions.pressKey(key: key, modifiers: modifiers)

    struct KeyResponse: Codable {
        let success: Bool
        let key: String
        let modifiers: [String]
        let targetApp: String?
    }

    let response = KeyResponse(success: true, key: key, modifiers: modifiers, targetApp: targetAppName)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
}
```

- [ ] **Step 7: Build**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Sources/ai-os-mcp/Tools/
git commit -m "feat: add all tool handlers — running apps, AX tree, click, type, press key"
```

---

### Task 12: Wire Up main.swift

**Files:**
- Modify: `Sources/ai-os-mcp/main.swift`

- [ ] **Step 1: Update main.swift with full server bootstrap**

```swift
import Foundation
import MCP

// MARK: - Stderr Output (stdout is reserved for MCP JSON-RPC)

var standardError = FileHandle.standardError

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}

func log(_ message: String) {
    print("[ai-os-mcp] \(message)", to: &standardError)
}

// MARK: - Main

log("Starting ai-os-mcp v0.1.0...")

// Check accessibility permission (with prompt)
let trusted = axCheckPermission()
if !trusted {
    log("⚠ Accessibility permission not granted.")
    log("  Open System Settings → Privacy & Security → Accessibility")
    log("  Add and enable this binary, then restart.")
    log("  Server will start but tools requiring AX access will return errors.")
}

// Create MCP server
let server = Server(
    name: "ai-os-mcp",
    version: "0.1.0",
    capabilities: Server.Capabilities(
        tools: .init(listChanged: false)
    )
)

// Register all tools
await registerTools(on: server)

log("MCP server ready. Waiting for connections on stdio...")

// Start stdio transport
let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()

log("Server shut down.")
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/ai-os-mcp/main.swift
git commit -m "feat: wire up main.swift with server bootstrap and permission check"
```

---

## Chunk 4: Project Files, CI, Installation

### Task 13: Create README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README.md**

Write a professional README with:
- Project description and the core insight (semantic AX tree vs screenshots)
- Architecture diagram (text-based)
- Prerequisites (macOS 13+, Swift 6.0+, Xcode 16+)
- Build instructions (`swift build -c release`)
- Installation instructions (manual and via install.sh)
- Claude Desktop configuration JSON
- Accessibility permission setup guide with screenshots description
- All 6 tools documented with example inputs/outputs
- How it works section explaining AX tree
- Comparison table vs screenshot-based approaches
- Contributing section
- License (MIT)

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add comprehensive README"
```

---

### Task 14: Create LICENSE, CONTRIBUTING.md

**Files:**
- Create: `LICENSE`
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: Create MIT LICENSE**

Standard MIT license with copyright "2026 Charan Tej Mandali"

- [ ] **Step 2: Create CONTRIBUTING.md**

Include:
- How to build from source
- How to run tests
- Code style (Swift standard)
- PR process
- Issue reporting guidelines

- [ ] **Step 3: Commit**

```bash
git add LICENSE CONTRIBUTING.md
git commit -m "docs: add MIT license and contributing guide"
```

---

### Task 15: Create install.sh

**Files:**
- Create: `scripts/install.sh`

- [ ] **Step 1: Create install.sh**

```bash
#!/bin/bash
set -euo pipefail

BINARY_NAME="ai-os-mcp"
INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/Library/Application Support/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

echo "🔨 Building $BINARY_NAME (release)..."
swift build -c release

BUILT_BINARY=".build/release/$BINARY_NAME"
if [ ! -f "$BUILT_BINARY" ]; then
    echo "❌ Build failed. Binary not found at $BUILT_BINARY"
    exit 1
fi

echo "📦 Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp "$BUILT_BINARY" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"
echo "✅ Installed: $BINARY_PATH"

# Configure Claude Desktop
echo ""
echo "🔧 Configuring Claude Desktop..."
mkdir -p "$CONFIG_DIR"

MCP_ENTRY="{\"command\":\"$BINARY_PATH\"}"

if [ -f "$CONFIG_FILE" ]; then
    # Check if jq is available
    if command -v jq &>/dev/null; then
        UPDATED=$(jq --argjson entry "$MCP_ENTRY" '.mcpServers["ai-os-mcp"] = $entry' "$CONFIG_FILE")
        echo "$UPDATED" > "$CONFIG_FILE"
        echo "✅ Updated existing Claude Desktop config"
    else
        echo "⚠️  jq not found. Please manually add to $CONFIG_FILE:"
        echo ""
        echo "  \"mcpServers\": {"
        echo "    \"ai-os-mcp\": { \"command\": \"$BINARY_PATH\" }"
        echo "  }"
    fi
else
    cat > "$CONFIG_FILE" << ENDJSON
{
  "mcpServers": {
    "ai-os-mcp": {
      "command": "$BINARY_PATH"
    }
  }
}
ENDJSON
    echo "✅ Created Claude Desktop config"
fi

echo ""
echo "🔐 Accessibility Permission"
echo "   1. Open System Settings → Privacy & Security → Accessibility"
echo "   2. Click + and add: $BINARY_PATH"
echo "   3. Toggle it ON"
echo "   4. Restart Claude Desktop"
echo ""
echo "🎉 Done! Restart Claude Desktop to use ai-os-mcp."
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x scripts/install.sh
git add scripts/install.sh
git commit -m "feat: add install script for build + Claude Desktop configuration"
```

---

### Task 16: Create GitHub Actions CI

**Files:**
- Create: `.github/workflows/build.yml`

- [ ] **Step 1: Create build.yml**

```yaml
name: Build & Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.0.app

      - name: Build
        run: swift build -c release

      - name: Test
        run: swift test

      - name: Upload binary
        if: github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: ai-os-mcp
          path: .build/release/ai-os-mcp
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: add GitHub Actions build and test workflow"
```

---

### Task 17: Create GitHub Repo and Push

- [ ] **Step 1: Create the repo on GitHub**

```bash
cd /Users/charantej/charan_personal_projects/ai-os-mcp
gh repo create charantejmandali18/ai-os-mcp --public --description "Native macOS MCP server that gives AI assistants direct semantic access to any app's UI through the Accessibility API. No screenshots, no coordinate math — pure structured data." --source=. --push
```

- [ ] **Step 2: Verify repo is live**

```bash
gh repo view charantejmandali18/ai-os-mcp --web
```

---

### Task 18: Build and Smoke Test

- [ ] **Step 1: Build release binary**

Run: `swift build -c release`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run all tests**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 3: Smoke test the binary**

Run: `.build/release/ai-os-mcp` (should print startup logs to stderr and wait for MCP input on stdin)
Kill with Ctrl+C after confirming it starts.

- [ ] **Step 4: Tag initial release**

```bash
git tag -a v0.1.0 -m "v0.1.0 — Phase 0: macOS Accessibility MCP Server"
git push origin v0.1.0
```
