import Foundation
import MCP

func handleMouseClickAt(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    actions: AXActions
) throws -> CallTool.Result {
    guard let x = params.arguments?["x"]?.doubleValue else {
        throw AIOSError.invalidArguments(detail: "x coordinate is required")
    }
    guard let y = params.arguments?["y"]?.doubleValue else {
        throw AIOSError.invalidArguments(detail: "y coordinate is required")
    }

    let buttonStr = params.arguments?["button"]?.stringValue ?? "left"
    let clickTypeStr = params.arguments?["click_type"]?.stringValue ?? "single"
    let appName = params.arguments?["app_name"]?.stringValue

    guard let button = AXActions.MouseButton(rawValue: buttonStr) else {
        throw AIOSError.invalidArguments(detail: "Invalid button: '\(buttonStr)'. Valid: left, right, middle")
    }
    guard let clickType = AXActions.ClickType(rawValue: clickTypeStr) else {
        throw AIOSError.invalidArguments(detail: "Invalid click_type: '\(clickTypeStr)'. Valid: single, double, triple")
    }

    if let appName = appName {
        let (pid, _) = try appResolver.resolve(appName: appName)
        actions.raiseApp(pid: pid)
        usleep(100_000)
    }

    try actions.mouseClick(x: x, y: y, button: button, clickType: clickType)

    struct ClickResponse: Codable {
        let success: Bool
        let x: Double
        let y: Double
        let button: String
        let clickType: String
    }

    let response = ClickResponse(success: true, x: x, y: y, button: buttonStr, clickType: clickTypeStr)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
