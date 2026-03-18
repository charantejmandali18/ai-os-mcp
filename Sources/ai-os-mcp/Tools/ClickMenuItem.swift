import AppKit
import ApplicationServices
import Foundation
import MCP

/// Parse a menu path like "File > Export > PDF" into segments.
func parseMenuPath(_ path: String) -> [String] {
    path.components(separatedBy: " > ").map { $0.trimmingCharacters(in: .whitespaces) }
}

/// Normalize a menu title for comparison: lowercase, strip ellipsis, trim.
func normalizeMenuTitle(_ title: String) -> String {
    var normalized = title.lowercased()
        .trimmingCharacters(in: .whitespaces)
    // Remove trailing ellipsis (both ASCII "..." and Unicode "\u{2026}")
    normalized = normalized.replacingOccurrences(of: "\u{2026}", with: "")
    while normalized.hasSuffix(".") {
        normalized = String(normalized.dropLast())
    }
    return normalized.trimmingCharacters(in: .whitespaces)
}

/// Check if a menu title matches a query (case-insensitive, ellipsis-normalized).
func menuTitleMatches(_ title: String, query: String) -> Bool {
    normalizeMenuTitle(title) == normalizeMenuTitle(query)
}

func handleClickMenuItem(
    params: CallTool.Parameters,
    appResolver: AppResolver
) throws -> CallTool.Result {
    guard axCheckPermissionSilent() else { throw AIOSError.permissionDenied }

    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard let menuPath = params.arguments?["menu_path"]?.stringValue else {
        throw AIOSError.invalidArguments(
            detail: "menu_path is required (e.g. 'File > Export > PDF')")
    }

    let segments = parseMenuPath(menuPath)
    if segments.isEmpty {
        throw AIOSError.invalidArguments(detail: "menu_path is empty")
    }

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 5.0)

    // Raise app
    if let app = NSRunningApplication(processIdentifier: pid) {
        app.activate(options: [])
    }
    usleep(200_000)

    guard let menuBarValue = axGetAttribute(appElement, kAXMenuBarAttribute) else {
        throw AIOSError.actionFailed(
            action: "click_menu_item", detail: "Could not access menu bar")
    }
    // swiftlint:disable:next force_cast
    let menuBar = menuBarValue as! AXUIElement

    // Navigate: MenuBar > MenuBarItem(segment[0]) > Menu > MenuItem(segment[1]) > ...
    var currentChildren = axGetChildren(menuBar)
    var currentPath = ""

    for (i, segment) in segments.enumerated() {
        let availableTitles = currentChildren.compactMap {
            axGetStringAttribute($0, kAXTitleAttribute)
        }.filter { !$0.isEmpty }

        guard
            let match = currentChildren.first(where: {
                guard let title = axGetStringAttribute($0, kAXTitleAttribute) else { return false }
                return menuTitleMatches(title, query: segment)
            })
        else {
            throw AIOSError.menuItemNotFound(
                path: segments[0...i].joined(separator: " > "),
                available: availableTitles
            )
        }

        currentPath += (currentPath.isEmpty ? "" : " > ") + segment

        if i == segments.count - 1 {
            // Final item — click it
            let result = AXUIElementPerformAction(match, kAXPressAction as CFString)
            if result != .success {
                throw AIOSError.actionFailed(
                    action: "click_menu_item", detail: axErrorDescription(result))
            }
        } else {
            // Intermediate item — press to open submenu, then get children
            AXUIElementPerformAction(match, kAXPressAction as CFString)
            usleep(100_000)  // Wait for submenu to open
            let subMenus = axGetChildren(match)
            currentChildren = []
            for sub in subMenus {
                currentChildren.append(contentsOf: axGetChildren(sub))
            }
        }
    }

    struct MenuClickResponse: Codable {
        let success: Bool
        let app: String
        let menuPath: String
    }
    let response = MenuClickResponse(success: true, app: resolvedName, menuPath: menuPath)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json =
        (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
