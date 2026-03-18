import Foundation

enum AIOSError: Error, CustomStringConvertible {
    case permissionDenied
    case appNotFound(name: String, available: [String])
    case elementNotFound(search: String)
    case appNotResponding(name: String)
    case actionFailed(action: String, detail: String)
    case invalidArguments(detail: String)
    case scriptTimeout(seconds: Int)
    case scriptError(message: String)
    case scriptBlocked(reason: String)
    case menuItemNotFound(path: String, available: [String])
    case pasteboardEmpty(format: String)
    case windowManagementFailed(app: String, action: String, detail: String)
    case invalidURL(url: String)
    case screenshotFailed(detail: String)
    case appLaunchFailed(name: String, detail: String)

    var description: String {
        switch self {
        case .permissionDenied:
            return """
                Accessibility permission required. \
                Open System Settings → Privacy & Security → Accessibility \
                and grant permission to ai-os-mcp.
                """
        case .appNotFound(let name, let available):
            return "App '\(name)' not found. Running apps: \(available.joined(separator: ", "))"
        case .elementNotFound(let search):
            return "No element matching '\(search)' found. Use get_ax_tree to inspect available elements."
        case .appNotResponding(let name):
            return "App '\(name)' is not responding to accessibility queries."
        case .actionFailed(let action, let detail):
            return "Failed to perform \(action): \(detail)"
        case .invalidArguments(let detail):
            return "Invalid arguments: \(detail)"
        case .scriptTimeout(let seconds):
            return "Script timeout after \(seconds) seconds."
        case .scriptError(let message):
            return "Script execution error: \(message)"
        case .scriptBlocked(let reason):
            return "Script blocked for safety: \(reason). Use press_key or click_element instead."
        case .menuItemNotFound(let path, let available):
            return "Menu item '\(path)' not found. Available items: \(available.joined(separator: ", "))"
        case .pasteboardEmpty(let format):
            return "Pasteboard has no content of type '\(format)'."
        case .windowManagementFailed(let app, let action, let detail):
            return "Window \(action) failed for '\(app)': \(detail)"
        case .invalidURL(let url):
            return "Invalid URL: '\(url)'"
        case .screenshotFailed(let detail):
            return "Screenshot failed: \(detail)"
        case .appLaunchFailed(let name, let detail):
            return "Failed to launch '\(name)': \(detail)"
        }
    }
}
