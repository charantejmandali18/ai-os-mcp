import AppKit
import Foundation
import MCP

/// Write content to pasteboard. Exported for testing.
func writePasteboardContent(content: String, format: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    switch format.lowercased() {
    case "html":
        pasteboard.setString(content, forType: .html)
        // Also write as plain text for apps that don't support HTML
        pasteboard.setString(content, forType: .string)
    default:
        pasteboard.setString(content, forType: .string)
    }
}

func handleWritePasteboard(params: CallTool.Parameters) throws -> CallTool.Result {
    guard let content = params.arguments?["content"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "content is required")
    }
    let format = params.arguments?["format"]?.stringValue ?? "text"

    if format != "text" && format != "html" {
        throw AIOSError.invalidArguments(detail: "write format must be 'text' or 'html'")
    }

    writePasteboardContent(content: content, format: format)

    struct WriteResponse: Codable {
        let success: Bool
        let format: String
        let length: Int
    }
    let response = WriteResponse(success: true, format: format, length: content.count)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json =
        (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
