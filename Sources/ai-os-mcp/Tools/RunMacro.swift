import ApplicationServices
import AppKit
import Foundation
import MCP

/// Execute multiple actions in sequence in ONE call. Only runs OCR once at the end.
func handleRunMacro(
    params: CallTool.Parameters,
    appResolver: AppResolver,
    actions: AXActions,
    screenCapture: ScreenCapture
) throws -> CallTool.Result {
    guard let appName = params.arguments?["app_name"]?.stringValue else {
        throw AIOSError.invalidArguments(detail: "app_name is required")
    }
    guard let stepsValue = params.arguments?["steps"]?.arrayValue else {
        throw AIOSError.invalidArguments(detail: "steps array is required")
    }

    let skipOcr = params.arguments?["skip_ocr"]?.boolValue ?? false

    let (pid, resolvedName) = try appResolver.resolve(appName: appName)
    actions.raiseApp(pid: pid)
    usleep(50_000)

    var results: [String] = []

    for stepValue in stepsValue {
        guard let step = stepValue.objectValue else {
            results.append("skipped: invalid step")
            continue
        }

        guard let actionName = step["action"]?.stringValue else {
            results.append("skipped: no action field")
            continue
        }

        do {
            let result = try executeAction(
                action: actionName, args: step, resolvedName: resolvedName,
                pid: pid, actions: actions
            )
            results.append(result)
        } catch {
            results.append("error: \(error)")
            break
        }
    }

    var response: [String: Any] = [
        "app": resolvedName,
        "stepsExecuted": results.count,
        "results": results,
    ]

    if !skipOcr {
        usleep(200_000)
        let (texts, screenW, screenH, _) = screenCapture.extractTexts()
        response["screenSize"] = [screenW, screenH]
        response["textCount"] = texts.count
        response["texts"] = texts.map { t in
            ["text": t.text, "x": t.x, "y": t.y, "w": t.width, "h": t.height] as [String: Any]
        }
    }

    let json = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
    return .init(content: [.text(String(data: json, encoding: .utf8) ?? "{}")], isError: false)
}
