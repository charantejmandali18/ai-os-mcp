import Foundation
import MCP

func handleGetRunningApps(appResolver: AppResolver) throws -> CallTool.Result {
    let apps = appResolver.listRunningApps()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(["apps": apps])
    let text = String(data: json, encoding: .utf8) ?? "[]"
    return .init(content: [.text(text)], isError: false)
}
