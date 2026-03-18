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
    let includeOcr = params.arguments?["include_ocr"]?.boolValue ?? true

    // Run OCR on latest frame — zero capture latency, ~50-250ms for text extraction
    var result: [String: Any] = ["success": true]

    let (texts, screenW, screenH, changed) = screenCapture.extractTexts()
    result["screenSize"] = [screenW, screenH]
    result["changed"] = changed

    if !changed {
        result["message"] = "Screen unchanged since last call"
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        let text = String(data: json, encoding: .utf8) ?? "{}"
        return .init(content: [.text(text)], isError: false)
    }

    // Add OCR texts with positions
    if includeOcr {
        result["texts"] = texts.map { t in
            [
                "text": t.text,
                "x": t.x, "y": t.y,
                "w": t.width, "h": t.height,
            ] as [String: Any]
        }
        result["textCount"] = texts.count
    }

    // Add AX tree elements if requested
    if includeAxTree, let appName = appName {
        if let (pid, _) = try? appResolver.resolve(appName: appName) {
            if let tree = treeReader.readTree(pid: pid, maxDepth: 3, maxChildren: 30) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                if let json = try? encoder.encode(tree), let text = String(data: json, encoding: .utf8) {
                    result["axTree"] = text
                }
            }
        }
    }

    let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    let text = String(data: json, encoding: .utf8) ?? "{}"
    return .init(content: [.text(text)], isError: false)
}
