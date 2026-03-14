import ApplicationServices
import Foundation
import MCP

func handleTypeText(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    search: AXElementSearch,
    actions: AXActions
) throws -> CallTool.Result {
    guard let text = params.arguments?["text"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "text is required")
    }

    let appName = params.arguments?["app_name"]?.stringValue
    let elementSearchQuery = params.arguments?["element_search"]?.stringValue

    var targetAppName: String?

    if let appName = appName {
        let (pid, resolvedName) = try appResolver.resolve(appName: appName)
        actions.raiseApp(pid: pid)
        targetAppName = resolvedName
        usleep(200_000)  // 200ms for app activation

        // If element_search is specified, find and focus the element
        if let query = elementSearchQuery {
            guard axCheckPermissionSilent() else { throw AIOSError.permissionDenied }

            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 2.0)

            let results = search.search(root: appElement, query: query)
            if results.isEmpty {
                throw AIOSError.elementNotFound(search: query)
            }

            actions.focusElement(results[0].element)
            usleep(50_000)  // 50ms for focus

            // Try direct value setting first (faster)
            if actions.setTextValue(results[0].element, text: text) {
                return makeTypeResponse(text: text, app: targetAppName)
            }
        }
    }

    // Fall back to CGEvent typing
    actions.typeTextViaCGEvent(text)
    return makeTypeResponse(text: text, app: targetAppName)
}

private func makeTypeResponse(text: String, app: String?) -> CallTool.Result {
    struct TypeResponse: Codable {
        let success: Bool
        let typed: String
        let targetApp: String?
    }

    let response = TypeResponse(success: true, typed: text, targetApp: app)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}
