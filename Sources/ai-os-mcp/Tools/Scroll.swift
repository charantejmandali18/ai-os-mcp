import ApplicationServices
import Foundation
import MCP

func handleScroll(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    search: AXElementSearch,
    actions: AXActions
) throws -> CallTool.Result {
    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard let direction = params.arguments?["direction"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "direction is required (up, down, left, right)")
    }

    let amount = params.arguments?["amount"]?.intValue ?? 3
    let elementSearchQuery = params.arguments?["element_search"]?.stringValue

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)
    actions.raiseApp(pid: pid)
    usleep(100_000)

    var scrollX: Double
    var scrollY: Double

    if let query = elementSearchQuery {
        guard axCheckPermissionSilent() else { throw AIOSError.permissionDenied }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 2.0)
        let results = search.search(root: appElement, query: query)
        if results.isEmpty {
            throw AIOSError.elementNotFound(search: query)
        }
        // Get element center position
        let element = results[0].element
        if let pos = axGetPosition(element), let size = axGetSize(element) {
            scrollX = pos.x + size.width / 2
            scrollY = pos.y + size.height / 2
        } else {
            throw AIOSError.actionFailed(action: "scroll", detail: "Could not get element position")
        }
    } else {
        // Scroll at center of app's frontmost window
        guard axCheckPermissionSilent() else { throw AIOSError.permissionDenied }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 2.0)
        let windowAttr = axGetAttribute(appElement, kAXFocusedWindowAttribute)
        // AXUIElement is a CFTypeRef alias, so use unsafeBitCast when the attribute is present
        if let windowAttr = windowAttr {
            let windowRef = unsafeDowncast(windowAttr as AnyObject, to: AXUIElement.self)
            if let pos = axGetPosition(windowRef), let size = axGetSize(windowRef) {
                scrollX = pos.x + size.width / 2
                scrollY = pos.y + size.height / 2
            } else {
                scrollX = 640
                scrollY = 400
            }
        } else {
            // Fallback: screen center
            scrollX = 640
            scrollY = 400
        }
    }

    try actions.scroll(direction: direction, amount: amount, atX: scrollX, atY: scrollY)

    struct ScrollResponse: Codable {
        let success: Bool
        let direction: String
        let amount: Int
        let targetApp: String
    }

    let response = ScrollResponse(success: true, direction: direction, amount: amount, targetApp: resolvedName)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
