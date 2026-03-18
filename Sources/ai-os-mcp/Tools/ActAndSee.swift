import ApplicationServices
import AppKit
import Foundation
import MCP

func handleActAndSee(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    search: AXElementSearch,
    actions: AXActions,
    screenCapture: ScreenCapture
) throws -> CallTool.Result {
    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard let action = params.arguments?["action"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "action is required (click, type, press_key, navigate)")
    }

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)
    actions.raiseApp(pid: pid)
    usleep(100_000)

    var actionResult = ""

    switch action.lowercased() {
    case "click":
        guard let searchQuery = params.arguments?["search"]?.stringValue else {
            throw AIOSError.invalidArguments(detail: "search is required for click action")
        }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 2.0)
        let results = search.search(root: appElement, query: searchQuery)
        if results.isEmpty {
            throw AIOSError.elementNotFound(search: searchQuery)
        }
        let index = params.arguments?["index"].flatMap({ Int($0) }) ?? 0
        guard index < results.count else {
            throw AIOSError.invalidArguments(detail: "index \(index) out of range. Found \(results.count) matches.")
        }
        try actions.pressElement(results[index].element)
        actionResult = "clicked '\(searchQuery)' (\(results.count) matches)"

    case "type":
        guard let text = params.arguments?["text"]?.stringValue else {
            throw AIOSError.invalidArguments(detail: "text is required for type action")
        }
        actions.typeTextViaCGEvent(text)
        actionResult = "typed '\(text)'"

    case "press_key":
        guard let key = params.arguments?["key"]?.stringValue else {
            throw AIOSError.invalidArguments(detail: "key is required for press_key action")
        }
        let modifiers = params.arguments?["modifiers"]?.arrayValue?.compactMap({ $0.stringValue }) ?? []
        try actions.pressKey(key: key, modifiers: modifiers)
        actionResult = "pressed '\(key)'"

    case "navigate":
        guard let url = params.arguments?["url"]?.stringValue else {
            throw AIOSError.invalidArguments(detail: "url is required for navigate action")
        }
        let fullURL = url.contains("://") ? url : "https://\(url)"
        let script = "tell application \"\(resolvedName)\" to open location \"\(fullURL)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        actionResult = "navigated to '\(fullURL)'"

    case "click_at":
        guard let xVal = params.arguments?["x"], let x = Double(xVal, strict: false) else {
            throw AIOSError.invalidArguments(detail: "x coordinate is required for click_at action")
        }
        guard let yVal = params.arguments?["y"], let y = Double(yVal, strict: false) else {
            throw AIOSError.invalidArguments(detail: "y coordinate is required for click_at action")
        }
        try actions.mouseClick(x: x, y: y, button: .left, clickType: .single)
        actionResult = "clicked at (\(Int(x)), \(Int(y)))"

    default:
        throw AIOSError.invalidArguments(detail: "Unknown action: '\(action)'. Valid: click, click_at, type, press_key, navigate")
    }

    // Wait briefly for the action to take effect, then run OCR on the result
    usleep(500_000) // 500ms for UI to update

    let (texts, screenW, screenH, _) = screenCapture.extractTexts()

    var result: [String: Any] = [
        "action": actionResult,
        "app": resolvedName,
        "screenSize": [screenW, screenH],
        "textCount": texts.count,
        "texts": texts.map { t in
            [
                "text": t.text,
                "x": t.x, "y": t.y,
                "w": t.width, "h": t.height,
            ] as [String: Any]
        },
    ]

    let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    let text = String(data: json, encoding: .utf8) ?? "{}"
    return .init(content: [.text(text)], isError: false)
}
