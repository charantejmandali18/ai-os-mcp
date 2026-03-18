import AppKit
import Foundation
import MCP

/// Read pasteboard content in the specified format. Exported for testing.
func readPasteboardContent(format: String) throws -> String {
    let pasteboard = NSPasteboard.general

    switch format.lowercased() {
    case "text":
        guard let text = pasteboard.string(forType: .string) else {
            throw AIOSError.pasteboardEmpty(format: "text")
        }
        return text

    case "html":
        guard let html = pasteboard.string(forType: .html) else {
            throw AIOSError.pasteboardEmpty(format: "html")
        }
        return html

    case "rtf":
        guard let data = pasteboard.data(forType: .rtf),
            let rtf = String(data: data, encoding: .utf8)
        else {
            throw AIOSError.pasteboardEmpty(format: "rtf")
        }
        return rtf

    case "file_urls":
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
            !urls.isEmpty
        else {
            throw AIOSError.pasteboardEmpty(format: "file_urls")
        }
        let paths = urls.map { $0.path }
        let data = try JSONSerialization.data(withJSONObject: paths, options: [])
        return String(data: data, encoding: .utf8) ?? "[]"

    default:
        throw AIOSError.invalidArguments(
            detail: "Unknown format: '\(format)'. Valid: text, html, rtf, file_urls")
    }
}

func handleReadPasteboard(params: CallTool.Parameters) throws -> CallTool.Result {
    let format = params.arguments?["format"]?.stringValue ?? "text"
    let content = try readPasteboardContent(format: format)

    struct PasteboardResponse: Codable {
        let success: Bool
        let format: String
        let content: String
    }
    let response = PasteboardResponse(success: true, format: format, content: content)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json =
        (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
