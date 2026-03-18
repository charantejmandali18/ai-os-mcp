import ApplicationServices
import Foundation
import MCP

func handleGetAXTree(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    treeReader: AXTreeReader
) throws -> CallTool.Result {
    guard axCheckPermissionSilent() else {
        throw AIOSError.permissionDenied
    }

    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }

    let maxDepth = params.arguments?["max_depth"].flatMap({ Int($0) }) ?? 5
    let maxChildren = params.arguments?["max_children"].flatMap({ Int($0) }) ?? 50
    let filter = params.arguments?["filter"]?.stringValue

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)

    guard let tree = treeReader.readTree(
        pid: pid,
        maxDepth: maxDepth,
        maxChildren: maxChildren,
        filter: filter
    ) else {
        throw AIOSError.appNotResponding(name: resolvedName)
    }

    struct TreeResponse: Codable {
        let app: String
        let pid: Int32
        let tree: AXNode
    }

    let response = TreeResponse(app: resolvedName, pid: pid, tree: tree)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try encoder.encode(response)
    let text = String(data: json, encoding: .utf8) ?? "{}"

    return .init(content: [.text(text)], isError: false)
}
