import ApplicationServices
import Foundation
import MCP

func handleGetScreen(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    screenCapture: ScreenCapture,
    treeReader: AXTreeReader
) throws -> CallTool.Result {
    let appName = params.arguments?["app_name"]?.stringValue
    let includeAxTree = params.arguments?["include_ax_tree"]?.boolValue ?? true
    let quality = params.arguments?["quality"].flatMap({ Double($0) }) ?? 0.6

    var imageBase64: String?
    var changed = true

    // Use the persistent stream's latest frame (zero capture latency)
    let (frame, didChange) = screenCapture.getLatestFrameBase64(quality: quality)
    imageBase64 = frame
    changed = didChange

    guard let base64 = imageBase64 else {
        throw AIOSError.screenshotFailed(detail: "No frame available. Screen capture may not have started yet.")
    }

    var content: [Tool.Content] = []

    // Add the image inline as base64 (only if screen changed)
    if changed {
        content.append(.image(data: base64, mimeType: "image/jpeg", metadata: nil))
    }

    // Add AX tree summary if requested and app specified
    if includeAxTree, let appName = appName {
        if let (pid, _) = try? appResolver.resolve(appName: appName) {
            if let tree = treeReader.readTree(pid: pid, maxDepth: 3, maxChildren: 20) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                if let json = try? encoder.encode(tree), let text = String(data: json, encoding: .utf8) {
                    content.append(.text("AX Tree:\n\(text)"))
                }
            }
        }
    }

    if !changed {
        content.append(.text("{\"changed\":false,\"message\":\"Screen unchanged since last call\"}"))
    }

    return .init(content: content, isError: false)
}
