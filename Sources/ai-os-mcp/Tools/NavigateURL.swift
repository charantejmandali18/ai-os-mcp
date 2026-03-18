import AppKit
import Foundation
import MCP

func handleNavigateURL(
    params: CallTool.Parameters,
    appResolver: AppResolver
) throws -> CallTool.Result {
    guard let url = params.arguments?["url"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "url is required")
    }
    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard URL(string: url) != nil, url.contains("://") || url.contains(".") else {
        throw AIOSError.invalidURL(url: url)
    }

    // Add https:// if no scheme
    let fullURL = url.contains("://") ? url : "https://\(url)"

    // Use AppleScript to activate and navigate in one shot
    let script = """
    tell application "\(appName)"
        activate
        open location "\(fullURL)"
    end tell
    """

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    let stderrPipe = Pipe()
    process.standardError = stderrPipe
    process.standardOutput = Pipe()
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw AIOSError.actionFailed(action: "navigate_url", detail: stderr)
    }

    struct NavigateResponse: Codable {
        let success: Bool
        let url: String
        let app: String
    }
    let response = NavigateResponse(success: true, url: fullURL, app: appName)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
