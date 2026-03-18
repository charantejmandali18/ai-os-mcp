import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import MCP

func handleTakeScreenshot(
    params: CallTool.Parameters,
    appResolver: AppResolver
) throws -> CallTool.Result {
    let appName = params.arguments?["app_name"]?.stringValue
    let maxWidth = params.arguments?["max_width"].flatMap({ Int($0) }) ?? 1280
    let maxHeight = params.arguments?["max_height"].flatMap({ Int($0) }) ?? 800
    let formatStr = params.arguments?["format"]?.stringValue ?? "jpeg"
    let quality = params.arguments?["quality"].flatMap({ Double($0) }) ?? 0.7

    // Clean up old screenshots
    cleanupOldScreenshots()

    let image: CGImage

    if let appName = appName {
        let (pid, _) = try appResolver.resolve(appName: appName)
        // Find the window for this app
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            throw AIOSError.screenshotFailed(detail: "Could not get window list")
        }

        var windowID: CGWindowID?
        for window in windowList {
            if let ownerPID = window[kCGWindowOwnerPID] as? pid_t, ownerPID == pid {
                if let wid = window[kCGWindowNumber] as? CGWindowID {
                    windowID = wid
                    break
                }
            }
        }

        guard let wid = windowID else {
            throw AIOSError.screenshotFailed(detail: "No visible window found for app")
        }

        guard let captured = CGWindowListCreateImage(.null, .optionIncludingWindow, wid, [.boundsIgnoreFraming]) else {
            throw AIOSError.screenshotFailed(detail: "CGWindowListCreateImage failed")
        }
        image = captured
    } else {
        // Full screen
        guard let captured = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, []) else {
            throw AIOSError.screenshotFailed(detail: "Full screen capture failed")
        }
        image = captured
    }

    // Scale image to fit within max dimensions
    let srcWidth = CGFloat(image.width)
    let srcHeight = CGFloat(image.height)
    let scaleW = CGFloat(maxWidth) / srcWidth
    let scaleH = CGFloat(maxHeight) / srcHeight
    let scale = min(scaleW, scaleH, 1.0) // Don't upscale

    let destWidth = Int(srcWidth * scale)
    let destHeight = Int(srcHeight * scale)

    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: destWidth,
        pixelsHigh: destHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
    NSGraphicsContext.current = context
    let nsImage = NSImage(cgImage: image, size: NSSize(width: srcWidth, height: srcHeight))
    nsImage.draw(in: NSRect(x: 0, y: 0, width: destWidth, height: destHeight))
    NSGraphicsContext.restoreGraphicsState()

    let fileExtension: String
    let data: Data?

    if formatStr == "png" {
        fileExtension = "png"
        data = bitmapRep.representation(using: .png, properties: [:])
    } else {
        fileExtension = "jpg"
        data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    guard let imageData = data else {
        throw AIOSError.screenshotFailed(detail: "Failed to encode image")
    }

    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let filePath = "/tmp/ai-os-mcp-screenshot-\(timestamp).\(fileExtension)"
    try imageData.write(to: URL(fileURLWithPath: filePath))

    struct ScreenshotResponse: Codable {
        let success: Bool
        let filePath: String
        let width: Int
        let height: Int
        let format: String
        let sizeBytes: Int
    }

    let response = ScreenshotResponse(
        success: true, filePath: filePath, width: destWidth, height: destHeight,
        format: fileExtension, sizeBytes: imageData.count
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(response)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return .init(content: [.text(json)], isError: false)
}

private func cleanupOldScreenshots() {
    let fm = FileManager.default
    let tmpDir = "/tmp"
    guard let files = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
    for file in files where file.hasPrefix("ai-os-mcp-screenshot-") {
        try? fm.removeItem(atPath: "\(tmpDir)/\(file)")
    }
}
