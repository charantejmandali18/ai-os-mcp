import Foundation

enum AIOSError: Error, CustomStringConvertible {
    case permissionDenied
    case appNotFound(name: String, available: [String])
    case elementNotFound(search: String)
    case appNotResponding(name: String)
    case actionFailed(action: String, detail: String)
    case invalidArguments(detail: String)

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
        }
    }
}
