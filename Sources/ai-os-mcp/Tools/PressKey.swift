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

    let modifiers: [String] =
        params.arguments?["modifiers"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    let appName = params.arguments?["app_name"]?.stringValue

    var targetAppName: String?

    if let appName = appName {
        let (pid, resolvedName) = try appResolver.resolve(appName: appName)
        actions.raiseApp(pid: pid)
        targetAppName = resolvedName
        usleep(100_000)  // 100ms
    }

    try actions.pressKey(key: key, modifiers: modifiers)

    struct KeyResponse: Codable {
        let success: Bool
        let key: String
        let modifiers: [String]
        let targetApp: String?
    }

    let response = KeyResponse(
        success: true, key: key, modifiers: modifiers, targetApp: targetAppName
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
