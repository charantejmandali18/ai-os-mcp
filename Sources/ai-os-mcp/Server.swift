import Foundation
import MCP

/// Registers all MCP tools and routes CallTool requests to the appropriate handlers.
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
                description: """
                    List all running GUI applications with their names, PIDs, and bundle IDs.
                    """,
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
                description: """
                    Read the semantic UI tree (accessibility tree) of a running application. \
                    Returns a structured JSON tree of every UI element — buttons, text fields, \
                    labels, lists, etc. Use this to understand what's on screen before acting.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Application name (case-insensitive, partial match)"),
                        ]),
                        "max_depth": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum tree depth (default: 5)"),
                        ]),
                        "max_children": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum children per node (default: 50)"),
                        ]),
                        "filter": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Only return subtrees containing elements matching this text"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("app_name")]),
                ])
            ),
            Tool(
                name: "click_element",
                description: """
                    Find a UI element by its title, identifier, or description and click it. \
                    No coordinate math — finds the element semantically in the accessibility \
                    tree and performs AXPress.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Target application name"),
                        ]),
                        "search": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Text to search for in element title, identifier, or description"
                            ),
                        ]),
                        "role": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Optional AX role filter (e.g., AXButton, AXMenuItem)"
                            ),
                        ]),
                        "index": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Which match to click if multiple found (0-indexed, default: 0)"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("app_name"), .string("search")]),
                ])
            ),
            Tool(
                name: "type_text",
                description: """
                    Type text into the focused element or a specific element found by search. \
                    Uses the fastest method available (direct value setting, falling back to \
                    keystroke simulation for Electron/web apps).
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("Text to type"),
                        ]),
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Optional: bring this app to front first"),
                        ]),
                        "element_search": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Optional: find and focus this element before typing"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("text")]),
                ])
            ),
            Tool(
                name: "press_key",
                description: """
                    Send a keyboard shortcut or special key. Supports modifiers \
                    (command, shift, option, control) and named keys (return, escape, \
                    tab, arrows, F-keys, etc.).
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "key": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Key: return, escape, tab, space, delete, up, down, left, right, f1-f12, or a single character"
                            ),
                        ]),
                        "modifiers": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string(
                                "Modifier keys: command, shift, option, control"
                            ),
                        ]),
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Optional: bring this app to front first"),
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
                return try handleGetAXTree(
                    params: params, appResolver: appResolver, treeReader: treeReader
                )
            case "click_element":
                return try handleClickElement(
                    params: params, appResolver: appResolver, search: elementSearch,
                    actions: axActions
                )
            case "type_text":
                return try handleTypeText(
                    params: params, appResolver: appResolver, search: elementSearch,
                    actions: axActions
                )
            case "press_key":
                return try handlePressKey(
                    params: params, appResolver: appResolver, actions: axActions
                )
            default:
                return .init(
                    content: [
                        .text("Unknown tool: \(params.name)")
                    ],
                    isError: true
                )
            }
        } catch let error as AIOSError {
            return .init(
                content: [.text(error.description)],
                isError: true
            )
        } catch {
            return .init(
                content: [.text("Internal error: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
}
