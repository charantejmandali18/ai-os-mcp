import Foundation
import MCP

func handleGetFrontmostApp(appResolver: AppResolver) throws -> CallTool.Result {
    guard let app = appResolver.frontmostApp() else {
        return .init(
            content: [.text("No frontmost application found")],
            isError: true
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try encoder.encode(app)
    let text = String(data: json, encoding: .utf8) ?? "{}"
    return .init(content: [.text(text)], isError: false)
}
