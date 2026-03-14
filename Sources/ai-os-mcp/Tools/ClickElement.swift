import ApplicationServices
import Foundation
import MCP

func handleClickElement(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    search: AXElementSearch,
    actions: AXActions
) throws -> CallTool.Result {
    guard axCheckPermissionSilent() else {
        throw AIOSError.permissionDenied
    }

    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard let query = params.arguments?["search"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "search is required")
    }

    let role = params.arguments?["role"]?.stringValue
    let index = params.arguments?["index"]?.intValue ?? 0

    let (pid, _) = try appResolver.resolve(appName: appName)
    let appElement = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appElement, 2.0)

    // Raise the app first
    actions.raiseApp(pid: pid)
    usleep(100_000)  // 100ms for app to come to front

    let results = search.search(root: appElement, query: query, role: role)

    if results.isEmpty {
        throw AIOSError.elementNotFound(search: query)
    }

    guard index < results.count else {
        throw AIOSError.invalidArguments(
            detail: "index \(index) out of range. Found \(results.count) matches."
        )
    }

    let target = results[index]
    try actions.pressElement(target.element)

    struct ClickResponse: Codable {
        let success: Bool
        let clicked: ClickedElement
        let matchCount: Int

        struct ClickedElement: Codable {
            let role: String
            let title: String?
        }
    }

    let response = ClickResponse(
        success: true,
        clicked: .init(role: target.role, title: target.title),
        matchCount: results.count
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try encoder.encode(response)
    let text = String(data: json, encoding: .utf8) ?? "{}"

    return .init(content: [.text(text)], isError: false)
}
