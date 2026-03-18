import Foundation
import MCP

func handleGetScreen(
    params: CallTool.Parameters,
    screenCapture: ScreenCapture
) throws -> CallTool.Result {
    let (texts, screenW, screenH, changed) = screenCapture.extractTexts()

    var result: [String: Any] = [
        "success": true,
        "screenSize": [screenW, screenH],
        "changed": changed,
    ]

    if !changed {
        result["message"] = "Screen unchanged since last call"
    } else {
        result["textCount"] = texts.count
        result["texts"] = texts.map { t in
            ["text": t.text, "x": t.x, "y": t.y, "w": t.width, "h": t.height] as [String: Any]
        }
    }

    let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    let text = String(data: json, encoding: .utf8) ?? "{}"
    return .init(content: [.text(text)], isError: false)
}
