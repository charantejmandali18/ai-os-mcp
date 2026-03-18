import ApplicationServices
import AppKit
import Foundation
import MCP

func handleActAndSee(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    actions: AXActions,
    screenCapture: ScreenCapture
) throws -> CallTool.Result {
    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard let action = params.arguments?["action"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "action is required")
    }
    let skipOcr = params.arguments?["skip_ocr"]?.boolValue ?? false

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)
    actions.raiseApp(pid: pid)
    usleep(50_000) // 50ms

    let actionResult = try executeAction(
        action: action, args: params.arguments, resolvedName: resolvedName,
        pid: pid, actions: actions
    )

    // Only run OCR if requested
    if skipOcr {
        let result: [String: Any] = ["action": actionResult, "app": resolvedName]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        return .init(content: [.text(String(data: json, encoding: .utf8) ?? "{}")], isError: false)
    }

    usleep(200_000) // 200ms for UI to update
    let (texts, screenW, screenH, _) = screenCapture.extractTexts()

    let result: [String: Any] = [
        "action": actionResult,
        "app": resolvedName,
        "screenSize": [screenW, screenH],
        "textCount": texts.count,
        "texts": texts.map { t in
            ["text": t.text, "x": t.x, "y": t.y, "w": t.width, "h": t.height] as [String: Any]
        },
    ]
    let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    return .init(content: [.text(String(data: json, encoding: .utf8) ?? "{}")], isError: false)
}

/// Shared action executor — used by both act_and_see and run_macro.
/// Accepts a generic dictionary of arguments so it works with both CallTool.Parameters and macro steps.
func executeAction(
    action: String,
    args: [String: Value]?,
    resolvedName: String,
    pid: pid_t,
    actions: AXActions
) throws -> String {
    switch action.lowercased() {
    case "click_at":
        guard let xVal = args?["x"], let x = Double(xVal, strict: false) else {
            throw AIOSError.invalidArguments(detail: "x is required for click_at")
        }
        guard let yVal = args?["y"], let y = Double(yVal, strict: false) else {
            throw AIOSError.invalidArguments(detail: "y is required for click_at")
        }
        try actions.mouseClick(x: x, y: y, button: .left, clickType: .single)
        return "clicked at (\(Int(x)), \(Int(y)))"

    case "type":
        guard let text = args?["text"]?.stringValue else {
            throw AIOSError.invalidArguments(detail: "text is required for type")
        }
        actions.typeTextViaCGEvent(text)
        return "typed \(text.count) chars"

    case "press_key":
        guard let key = args?["key"]?.stringValue else {
            throw AIOSError.invalidArguments(detail: "key is required for press_key")
        }
        let modifiers = args?["modifiers"]?.arrayValue?.compactMap({ $0.stringValue }) ?? []
        try actions.pressKey(key: key, modifiers: modifiers)
        return "pressed '\(key)'"

    case "navigate":
        guard let url = args?["url"]?.stringValue else {
            throw AIOSError.invalidArguments(detail: "url is required for navigate")
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
        return "navigated to '\(fullURL)'"

    case "wait":
        let ms = args?["ms"].flatMap({ Int($0, strict: false) }) ?? 1000
        usleep(UInt32(ms) * 1000)
        return "waited \(ms)ms"

    default:
        throw AIOSError.invalidArguments(detail: "Unknown action: '\(action)'. Valid: click_at, type, press_key, navigate, wait")
    }
}
