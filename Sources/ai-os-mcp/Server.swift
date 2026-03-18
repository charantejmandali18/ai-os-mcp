import Foundation
import MCP

/// Registers all MCP tools and routes CallTool requests to the appropriate handlers.
func registerTools(on server: Server, screenCapture: ScreenCapture) async {
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
            Tool(
                name: "scroll",
                description: """
                    Scroll within an app or specific element. Finds the target window \
                    or element and delivers scroll wheel events there.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Target application name"),
                        ]),
                        "direction": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("up"), .string("down"),
                                .string("left"), .string("right"),
                            ]),
                            "description": .string("Scroll direction"),
                        ]),
                        "amount": .object([
                            "type": .string("integer"),
                            "description": .string("Number of scroll increments (default: 3)"),
                        ]),
                        "element_search": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Optional: scroll within a specific element found by this text"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("app_name"), .string("direction")]),
                ])
            ),
            Tool(
                name: "mouse_click_at",
                description: """
                    Raw coordinate-based mouse click. Fallback when semantic element \
                    search fails. Uses macOS global coordinate system.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "x": .object([
                            "type": .string("number"),
                            "description": .string("Screen x coordinate (global macOS coordinates)"),
                        ]),
                        "y": .object([
                            "type": .string("number"),
                            "description": .string("Screen y coordinate"),
                        ]),
                        "button": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("left"), .string("right"), .string("middle"),
                            ]),
                            "description": .string("Mouse button (default: left)"),
                        ]),
                        "click_type": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("single"), .string("double"), .string("triple"),
                            ]),
                            "description": .string("Click type (default: single)"),
                        ]),
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Optional: raise this app before clicking"),
                        ]),
                    ]),
                    "required": .array([.string("x"), .string("y")]),
                ])
            ),
            Tool(
                name: "mouse_drag",
                description: """
                    Drag from one point to another. Uses macOS global coordinate system \
                    with smooth movement over the specified duration.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "from_x": .object([
                            "type": .string("number"),
                            "description": .string("Start x coordinate"),
                        ]),
                        "from_y": .object([
                            "type": .string("number"),
                            "description": .string("Start y coordinate"),
                        ]),
                        "to_x": .object([
                            "type": .string("number"),
                            "description": .string("End x coordinate"),
                        ]),
                        "to_y": .object([
                            "type": .string("number"),
                            "description": .string("End y coordinate"),
                        ]),
                        "duration": .object([
                            "type": .string("number"),
                            "description": .string(
                                "Drag duration in seconds for smooth movement (default: 0.5)"
                            ),
                        ]),
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Optional: raise this app before dragging"),
                        ]),
                    ]),
                    "required": .array([
                        .string("from_x"), .string("from_y"),
                        .string("to_x"), .string("to_y"),
                    ]),
                ])
            ),
            Tool(
                name: "take_screenshot",
                description: """
                    Capture a screenshot of a specific app window or the full screen. \
                    Returns a file path to the saved image. Use as a last resort when \
                    structured data (AX tree, DOM) is not available.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Capture this app's window. Omit for full screen."
                            ),
                        ]),
                        "max_width": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Max width in pixels, image scaled to fit (default: 1280)"
                            ),
                        ]),
                        "max_height": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Max height in pixels (default: 800)"
                            ),
                        ]),
                        "format": .object([
                            "type": .string("string"),
                            "enum": .array([.string("png"), .string("jpeg")]),
                            "description": .string(
                                "Image format (default: jpeg). JPEG is 5-10x smaller."
                            ),
                        ]),
                        "quality": .object([
                            "type": .string("number"),
                            "description": .string(
                                "JPEG quality 0.0-1.0 (default: 0.7). Ignored for PNG."
                            ),
                        ]),
                    ]),
                ])
            ),
            Tool(
                name: "open_application",
                description: """
                    Launch an application by name or bundle ID. If already running, \
                    brings it to the front.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string(
                                "App display name (e.g. 'Safari') or bundle ID (e.g. 'com.apple.Safari')"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("app_name")]),
                ])
            ),
            Tool(
                name: "open_url",
                description: "Open a URL in the default browser.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "url": .object([
                            "type": .string("string"),
                            "description": .string("URL to open"),
                        ]),
                    ]),
                    "required": .array([.string("url")]),
                ])
            ),
            Tool(
                name: "navigate_url",
                description: """
                    Open a URL in a specific browser app. Activates the app and navigates \
                    in one fast call. Works with any browser (Chrome, Dia, Safari, Arc, Firefox).
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "url": .object([
                            "type": .string("string"),
                            "description": .string("URL to open"),
                        ]),
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Browser app name (e.g. 'Google Chrome', 'Dia', 'Safari', 'Arc')"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("url"), .string("app_name")]),
                ])
            ),
            Tool(
                name: "manage_window",
                description: """
                    Resize, move, minimize, maximize, fullscreen, or restore a window. \
                    Uses accessibility APIs to manipulate window position and size.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Target application name"),
                        ]),
                        "action": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("resize"), .string("move"),
                                .string("minimize"), .string("maximize"),
                                .string("fullscreen"), .string("restore"),
                            ]),
                            "description": .string("Window action to perform"),
                        ]),
                        "x": .object([
                            "type": .string("number"),
                            "description": .string("X position (required for 'move')"),
                        ]),
                        "y": .object([
                            "type": .string("number"),
                            "description": .string("Y position (required for 'move')"),
                        ]),
                        "width": .object([
                            "type": .string("number"),
                            "description": .string("Width (required for 'resize')"),
                        ]),
                        "height": .object([
                            "type": .string("number"),
                            "description": .string("Height (required for 'resize')"),
                        ]),
                    ]),
                    "required": .array([.string("app_name"), .string("action")]),
                ])
            ),
            Tool(
                name: "run_applescript",
                description: """
                    Execute AppleScript or JXA (JavaScript for Automation) code. \
                    Useful for scriptable apps like Finder, Mail, Safari. \
                    Scripts containing 'do shell script' are blocked for safety.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "script": .object([
                            "type": .string("string"),
                            "description": .string("The script source code to execute"),
                        ]),
                        "language": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("applescript"), .string("javascript"),
                            ]),
                            "description": .string(
                                "Script language (default: applescript). Use 'javascript' for JXA."
                            ),
                        ]),
                    ]),
                    "required": .array([.string("script")]),
                ])
            ),
            Tool(
                name: "get_menu_bar",
                description: """
                    Read all menu bar items for an app. Returns a structured JSON tree \
                    with menu titles, item names, enabled state, and keyboard shortcuts.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Target application name"),
                        ]),
                    ]),
                    "required": .array([.string("app_name")]),
                ])
            ),
            Tool(
                name: "click_menu_item",
                description: """
                    Click a menu item by path. Navigate the menu hierarchy using \
                    ' > ' as separator (e.g. 'File > Export > PDF'). Matching is \
                    case-insensitive with ellipsis normalization.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Target application name"),
                        ]),
                        "menu_path": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Menu path with ' > ' separator (e.g. 'File > Export > PDF')"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("app_name"), .string("menu_path")]),
                ])
            ),
            Tool(
                name: "read_pasteboard",
                description: """
                    Read clipboard contents in the specified format. Supports text, \
                    HTML, RTF, and file URLs.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "format": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("text"), .string("html"),
                                .string("rtf"), .string("file_urls"),
                            ]),
                            "description": .string(
                                "Content format to read (default: text)"
                            ),
                        ]),
                    ]),
                ])
            ),
            Tool(
                name: "write_pasteboard",
                description: """
                    Write content to the clipboard. Supports text and HTML formats.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Content to write to clipboard"),
                        ]),
                        "format": .object([
                            "type": .string("string"),
                            "enum": .array([.string("text"), .string("html")]),
                            "description": .string(
                                "Content format (default: text)"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("content")]),
                ])
            ),
            Tool(
                name: "get_screen",
                description: """
                    Get the current screen as an inline image with zero capture latency. \
                    Uses a persistent display stream — the frame is already in memory. \
                    Optionally includes a compact AX tree summary for an app. \
                    Returns nothing if the screen hasn't changed since last call.
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Optional: include AX tree summary for this app"
                            ),
                        ]),
                        "include_ax_tree": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "Include AX tree summary (default: true)"
                            ),
                        ]),
                        "quality": .object([
                            "type": .string("number"),
                            "description": .string(
                                "JPEG quality 0.0-1.0 (default: 0.6)"
                            ),
                        ]),
                    ]),
                ])
            ),
            Tool(
                name: "act_and_see",
                description: """
                    Perform an action AND return the resulting screen in ONE call. \
                    Eliminates the act-then-screenshot round-trip. Actions: click \
                    (by AX element search), type, press_key, navigate (open URL in app).
                    """,
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_name": .object([
                            "type": .string("string"),
                            "description": .string("Target application name"),
                        ]),
                        "action": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("click"), .string("click_at"), .string("type"),
                                .string("press_key"), .string("navigate"),
                            ]),
                            "description": .string("Action to perform"),
                        ]),
                        "search": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Element search text (for click action)"
                            ),
                        ]),
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("Text to type (for type action)"),
                        ]),
                        "key": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Key to press (for press_key action)"
                            ),
                        ]),
                        "modifiers": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string(
                                "Modifier keys for press_key (command, shift, option, control)"
                            ),
                        ]),
                        "url": .object([
                            "type": .string("string"),
                            "description": .string(
                                "URL to open (for navigate action)"
                            ),
                        ]),
                        "index": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Which match to click (0-indexed, for click action)"
                            ),
                        ]),
                        "x": .object([
                            "type": .string("number"),
                            "description": .string(
                                "Screen x coordinate (for click_at action)"
                            ),
                        ]),
                        "y": .object([
                            "type": .string("number"),
                            "description": .string(
                                "Screen y coordinate (for click_at action)"
                            ),
                        ]),
                    ]),
                    "required": .array([.string("app_name"), .string("action")]),
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
            case "scroll":
                return try handleScroll(
                    params: params, appResolver: appResolver, search: elementSearch,
                    actions: axActions
                )
            case "mouse_click_at":
                return try handleMouseClickAt(
                    params: params, appResolver: appResolver, actions: axActions
                )
            case "mouse_drag":
                return try handleMouseDrag(
                    params: params, appResolver: appResolver, actions: axActions
                )
            case "take_screenshot":
                return try handleTakeScreenshot(
                    params: params, appResolver: appResolver
                )
            case "open_application":
                return try handleOpenApplication(
                    params: params, appResolver: appResolver, actions: axActions
                )
            case "open_url":
                return try handleOpenURL(params: params)
            case "navigate_url":
                return try handleNavigateURL(params: params, appResolver: appResolver)
            case "manage_window":
                return try handleManageWindow(
                    params: params, appResolver: appResolver
                )
            case "run_applescript":
                return try handleRunAppleScript(params: params)
            case "get_menu_bar":
                return try handleGetMenuBar(
                    params: params, appResolver: appResolver
                )
            case "click_menu_item":
                return try handleClickMenuItem(
                    params: params, appResolver: appResolver
                )
            case "read_pasteboard":
                return try handleReadPasteboard(params: params)
            case "write_pasteboard":
                return try handleWritePasteboard(params: params)
            case "get_screen":
                return try handleGetScreen(
                    params: params, appResolver: appResolver,
                    screenCapture: screenCapture, treeReader: treeReader
                )
            case "act_and_see":
                return try handleActAndSee(
                    params: params, appResolver: appResolver,
                    search: elementSearch, actions: axActions,
                    screenCapture: screenCapture
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
