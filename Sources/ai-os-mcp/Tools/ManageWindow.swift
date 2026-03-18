import ApplicationServices
import AppKit
import Foundation
import MCP

/// Helper to extract AXUIElement from a CFTypeRef returned by axGetAttribute.
/// AXUIElement is a CFTypeRef typealias so the cast always succeeds when non-nil.
private func axElement(from ref: CFTypeRef?) -> AXUIElement? {
    guard let ref = ref else { return nil }
    // CFTypeRef and AXUIElement are both AnyObject; this is always valid for AX attributes
    // that return element references.
    return (ref as! AXUIElement)  // swiftlint:disable:this force_cast
}

func handleManageWindow(
    params: CallTool.Parameters,
    appResolver: AppResolver
) throws -> CallTool.Result {
    guard axCheckPermissionSilent() else { throw AIOSError.permissionDenied }

    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard let action = params.arguments?["action"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "action is required (resize, move, minimize, maximize, fullscreen, restore)")
    }

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 2.0)

    // Get the focused window
    guard let windowRef = axElement(from: axGetAttribute(appElement, kAXFocusedWindowAttribute)) else {
        throw AIOSError.windowManagementFailed(app: resolvedName, action: action, detail: "No focused window found")
    }

    switch action.lowercased() {
    case "move":
        guard let x = params.arguments?["x"]?.doubleValue,
              let y = params.arguments?["y"]?.doubleValue else {
            throw AIOSError.invalidArguments(detail: "move requires x and y parameters")
        }
        var point = CGPoint(x: x, y: y)
        let axValue = AXValueCreate(.cgPoint, &point)!
        let result = AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute as CFString, axValue)
        if result != .success {
            throw AIOSError.windowManagementFailed(app: resolvedName, action: action, detail: axErrorDescription(result))
        }

    case "resize":
        guard let width = params.arguments?["width"]?.doubleValue,
              let height = params.arguments?["height"]?.doubleValue else {
            throw AIOSError.invalidArguments(detail: "resize requires width and height parameters")
        }
        var size = CGSize(width: width, height: height)
        let axValue = AXValueCreate(.cgSize, &size)!
        let result = AXUIElementSetAttributeValue(windowRef, kAXSizeAttribute as CFString, axValue)
        if result != .success {
            throw AIOSError.windowManagementFailed(app: resolvedName, action: action, detail: axErrorDescription(result))
        }

    case "minimize":
        let result = AXUIElementSetAttributeValue(windowRef, kAXMinimizedAttribute as CFString, true as CFTypeRef)
        if result != .success {
            throw AIOSError.windowManagementFailed(app: resolvedName, action: action, detail: axErrorDescription(result))
        }

    case "restore":
        // Try un-minimize first
        let minResult = AXUIElementSetAttributeValue(windowRef, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        if minResult != .success {
            // Try exiting fullscreen
            let windowActions = axGetActions(windowRef)
            if windowActions.contains("AXZoomWindow") {
                AXUIElementPerformAction(windowRef, "AXZoomWindow" as CFString)
            }
        }

    case "maximize":
        // Fill screen without entering fullscreen
        guard let screen = NSScreen.main else {
            throw AIOSError.windowManagementFailed(app: resolvedName, action: action, detail: "No main screen found")
        }
        let visibleFrame = screen.visibleFrame
        // visibleFrame accounts for menu bar and dock
        var point = CGPoint(x: visibleFrame.origin.x, y: screen.frame.height - visibleFrame.origin.y - visibleFrame.height)
        var size = CGSize(width: visibleFrame.width, height: visibleFrame.height)
        let posValue = AXValueCreate(.cgPoint, &point)!
        let sizeValue = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(windowRef, kAXSizeAttribute as CFString, sizeValue)

    case "fullscreen":
        guard let button = axElement(from: axGetAttribute(windowRef, kAXFullScreenButtonAttribute)) else {
            throw AIOSError.windowManagementFailed(app: resolvedName, action: action, detail: "App does not support fullscreen")
        }
        AXUIElementPerformAction(button, kAXPressAction as CFString)

    default:
        throw AIOSError.invalidArguments(
            detail: "Unknown action: '\(action)'. Valid: resize, move, minimize, maximize, fullscreen, restore"
        )
    }

    struct WindowResponse: Codable {
        let success: Bool
        let app: String
        let action: String
    }
    let response = WindowResponse(success: true, app: resolvedName, action: action)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
