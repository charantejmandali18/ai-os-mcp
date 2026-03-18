import AppKit
import ApplicationServices
import Foundation
import MCP

func handleGetMenuBar(
    params: CallTool.Parameters,
    appResolver: AppResolver
) throws -> CallTool.Result {
    guard axCheckPermissionSilent() else { throw AIOSError.permissionDenied }

    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 5.0)

    // Raise app so menu bar is populated
    if let app = NSRunningApplication(processIdentifier: pid) {
        app.activate(options: [])
    }
    usleep(200_000)

    guard let menuBarValue = axGetAttribute(appElement, kAXMenuBarAttribute) else {
        throw AIOSError.actionFailed(
            action: "get_menu_bar",
            detail: "Could not access menu bar for '\(resolvedName)'"
        )
    }
    // swiftlint:disable:next force_cast
    let menuBar = menuBarValue as! AXUIElement

    let children = axGetChildren(menuBar)
    var menus: [[String: Any]] = []

    for menuBarItem in children {
        let title = axGetStringAttribute(menuBarItem, kAXTitleAttribute) ?? ""
        if title.isEmpty { continue }

        var items: [[String: Any]] = []
        let subMenu = axGetChildren(menuBarItem)
        for submenuContainer in subMenu {
            let menuItems = axGetChildren(submenuContainer)
            for item in menuItems {
                let itemTitle = axGetStringAttribute(item, kAXTitleAttribute) ?? ""
                if itemTitle.isEmpty { continue }
                let enabled = axGetBoolAttribute(item, kAXEnabledAttribute) ?? true
                let shortcut = axGetStringAttribute(item, "AXMenuItemCmdChar")
                var entry: [String: Any] = [
                    "title": itemTitle,
                    "enabled": enabled,
                ]
                if let shortcut = shortcut, !shortcut.isEmpty {
                    entry["shortcut"] = shortcut
                }
                items.append(entry)
            }
        }

        menus.append([
            "menu": title,
            "items": items,
        ])
    }

    // Use JSONSerialization for the dynamic menu structure
    let responseDict: [String: Any] = [
        "success": true,
        "app": resolvedName,
        "menus": menus,
    ]
    let json = try JSONSerialization.data(withJSONObject: responseDict, options: [.sortedKeys])
    let text = String(data: json, encoding: .utf8) ?? "{}"
    return .init(content: [.text(text)], isError: false)
}
