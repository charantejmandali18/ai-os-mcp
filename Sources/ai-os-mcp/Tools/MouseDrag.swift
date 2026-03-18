import Foundation
import MCP

func handleMouseDrag(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    actions: AXActions
) throws -> CallTool.Result {
    guard let fromXVal = params.arguments?["from_x"], let fromX = Double(fromXVal) else {
        throw AIOSError.invalidArguments(detail: "from_x is required")
    }
    guard let fromYVal = params.arguments?["from_y"], let fromY = Double(fromYVal) else {
        throw AIOSError.invalidArguments(detail: "from_y is required")
    }
    guard let toXVal = params.arguments?["to_x"], let toX = Double(toXVal) else {
        throw AIOSError.invalidArguments(detail: "to_x is required")
    }
    guard let toYVal = params.arguments?["to_y"], let toY = Double(toYVal) else {
        throw AIOSError.invalidArguments(detail: "to_y is required")
    }

    let duration = params.arguments?["duration"].flatMap({ Double($0) }) ?? 0.5
    let appName = params.arguments?["app_name"]?.stringValue

    if let appName = appName {
        let (pid, _) = try appResolver.resolve(appName: appName)
        actions.raiseApp(pid: pid)
        usleep(100_000)
    }

    try actions.mouseDrag(fromX: fromX, fromY: fromY, toX: toX, toY: toY, duration: duration)

    struct DragResponse: Codable {
        let success: Bool
        let fromX: Double
        let fromY: Double
        let toX: Double
        let toY: Double
    }

    let response = DragResponse(success: true, fromX: fromX, fromY: fromY, toX: toX, toY: toY)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
