import Foundation
import MCP

/// Check if a script contains dangerous patterns.
func isScriptBlocked(_ script: String) -> Bool {
    let lower = script.lowercased()
    let blockedPatterns = [
        "do shell script",
        "run shell script",
    ]
    return blockedPatterns.contains { lower.contains($0) }
}

func handleRunAppleScript(params: CallTool.Parameters) throws -> CallTool.Result {
    guard let script = params.arguments?["script"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "script is required")
    }

    let language = params.arguments?["language"]?.stringValue ?? "applescript"

    // Safety check
    if isScriptBlocked(script) {
        throw AIOSError.scriptBlocked(
            reason:
                "Script contains 'do shell script' or 'run shell script'. Use press_key or type_text to interact with Terminal instead."
        )
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

    if language == "javascript" {
        process.arguments = ["-l", "JavaScript", "-e", script]
    } else {
        process.arguments = ["-e", script]
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    // Enforce 30-second timeout using a flag
    nonisolated(unsafe) var didTimeout = false
    let timeoutQueue = DispatchQueue(label: "applescript-timeout")
    let timeoutItem = DispatchWorkItem {
        didTimeout = true
        process.terminate()
    }
    timeoutQueue.asyncAfter(deadline: .now() + 30, execute: timeoutItem)

    process.waitUntilExit()
    timeoutItem.cancel()

    let stdout =
        String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let stderr =
        String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if didTimeout {
        throw AIOSError.scriptTimeout(seconds: 30)
    }

    if process.terminationStatus != 0 {
        throw AIOSError.scriptError(
            message: stderr.isEmpty ? "Exit code \(process.terminationStatus)" : stderr)
    }

    struct ScriptResponse: Codable {
        let success: Bool
        let output: String
        let language: String
    }
    let response = ScriptResponse(success: true, output: stdout, language: language)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json =
        (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
