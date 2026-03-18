import AppKit
import Foundation
import MCP

func handleOpenURL(params: CallTool.Parameters) throws -> CallTool.Result {
    guard let urlString = params.arguments?["url"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "url is required")
    }
    guard let url = URL(string: urlString), url.scheme != nil else {
        throw AIOSError.invalidURL(url: urlString)
    }

    NSWorkspace.shared.open(url)

    struct URLResponse: Codable {
        let success: Bool
        let url: String
    }
    let response = URLResponse(success: true, url: urlString)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
