import AppKit
import Foundation
import MCP

func handleOpenApplication(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    actions: AXActions
) throws -> CallTool.Result {
    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }

    let workspace = NSWorkspace.shared

    // Check if it looks like a bundle ID (contains dots)
    if appName.contains(".") {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: appName) else {
            throw AIOSError.appLaunchFailed(name: appName, detail: "No app found with bundle ID '\(appName)'")
        }
        let config = NSWorkspace.OpenConfiguration()
        // Use synchronous approach: open and wait briefly
        var launched = false
        var launchError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        workspace.openApplication(at: appURL, configuration: config) { app, error in
            launched = (app != nil)
            launchError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)

        if let error = launchError {
            throw AIOSError.appLaunchFailed(name: appName, detail: error.localizedDescription)
        }

        return makeLaunchResponse(name: appName, bundleId: appName, launched: launched)
    }

    // Try to find by name among running apps first
    if let (pid, resolvedName) = try? appResolver.resolve(appName: appName) {
        // Already running — just bring to front
        actions.raiseApp(pid: pid)
        let app = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
        return makeLaunchResponse(name: resolvedName, bundleId: app?.bundleIdentifier, launched: true)
    }

    // Not running — try to open by name
    // Search in /Applications and ~/Applications
    let searchPaths = ["/Applications", "\(NSHomeDirectory())/Applications"]
    for searchPath in searchPaths {
        let appPath = "\(searchPath)/\(appName).app"
        if FileManager.default.fileExists(atPath: appPath) {
            let appURL = URL(fileURLWithPath: appPath)
            let config = NSWorkspace.OpenConfiguration()
            var launched = false
            let semaphore = DispatchSemaphore(value: 0)
            workspace.openApplication(at: appURL, configuration: config) { app, _ in
                launched = (app != nil)
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 10)
            return makeLaunchResponse(name: appName, bundleId: nil, launched: launched)
        }
    }

    // Last resort: use `open -a` which does fuzzy matching
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", appName]
    let pipe = Pipe()
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorMsg = String(data: errorData, encoding: .utf8) ?? "unknown error"
        throw AIOSError.appLaunchFailed(name: appName, detail: errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return makeLaunchResponse(name: appName, bundleId: nil, launched: true)
}

private func makeLaunchResponse(name: String, bundleId: String?, launched: Bool) -> CallTool.Result {
    struct LaunchResponse: Codable {
        let success: Bool
        let app: String
        let bundleId: String?
    }
    let response = LaunchResponse(success: launched, app: name, bundleId: bundleId)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
