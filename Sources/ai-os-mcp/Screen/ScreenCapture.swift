import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import AppKit
import Foundation
import Vision

/// Persistent screen capture engine using ScreenCaptureKit.
/// Maintains a ~2 FPS stream of the full display and keeps the latest frame
/// available for instant retrieval. Supports on-demand window capture by PID.
final class ScreenCapture: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var latestFrame: CGImage?
    private var frameHash: UInt64 = 0
    private var lastSentHash: UInt64 = 0
    private let lock = NSLock()
    private var isRunning = false
    private var actualScreenWidth: Int = 1512
    private var actualScreenHeight: Int = 982
    private static let captureWidth = 1280
    private static let captureHeight = 800

    // MARK: - Persistent Stream

    /// Start persistent capture of the full display at ~2 FPS.
    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw AIOSError.screenshotFailed(detail: "No display found")
        }

        // Store actual screen dimensions for coordinate scaling
        setScreenDimensions(width: display.width, height: display.height)

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.width = 1280
        config.height = 800
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2) // 2 FPS
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(
            self, type: .screen,
            sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated)
        )
        try await newStream.startCapture()

        setStreamRunning(newStream)
    }

    /// Stop the persistent capture stream.
    func stop() async {
        let currentStream = clearStream()
        try? await currentStream?.stopCapture()
    }

    // MARK: - Lock Helpers (synchronous, safe to call from any context)

    private func setStreamRunning(_ newStream: SCStream) {
        lock.lock()
        stream = newStream
        isRunning = true
        lock.unlock()
    }

    private func setScreenDimensions(width: Int, height: Int) {
        lock.lock()
        actualScreenWidth = width
        actualScreenHeight = height
        lock.unlock()
    }

    private func clearStream() -> SCStream? {
        lock.lock()
        let currentStream = stream
        stream = nil
        isRunning = false
        lock.unlock()
        return currentStream
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let hash = computeFrameHash(cgImage)

        lock.lock()
        latestFrame = cgImage
        frameHash = hash
        lock.unlock()
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        isRunning = false
        lock.unlock()
    }

    // MARK: - Frame Retrieval

    /// Get the latest frame as a base64-encoded JPEG string.
    /// Returns `(base64String, didChange)` where `didChange` indicates whether the
    /// frame differs from the one returned by the previous call.
    func getLatestFrameBase64(quality: Double = 0.6) -> (String?, Bool) {
        lock.lock()
        let frame = latestFrame
        let hash = frameHash
        let changed = hash != lastSentHash
        if changed { lastSentHash = hash }
        lock.unlock()

        guard let frame = frame else { return (nil, false) }

        let bitmapRep = NSBitmapImageRep(cgImage: frame)
        guard let data = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            return (nil, false)
        }
        return (data.base64EncodedString(), changed)
    }

    /// Get the latest frame as a CGImage.
    func getLatestFrame() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return latestFrame
    }

    /// Write the latest frame to a temp file and return the path.
    /// Uses PNG for lossless quality — no encode/decode overhead for Claude.
    /// Returns `(filePath, didChange)`.
    private static let tempPath = "/tmp/ai-os-mcp-screen.png"

    func getLatestFramePath() -> (String?, Bool) {
        lock.lock()
        let frame = latestFrame
        let hash = frameHash
        let changed = hash != lastSentHash
        if changed { lastSentHash = hash }
        lock.unlock()

        guard let frame = frame else { return (nil, false) }
        guard changed else { return (Self.tempPath, false) }

        let bitmapRep = NSBitmapImageRep(cgImage: frame)
        guard let data = bitmapRep.representation(using: .png, properties: [:]) else {
            return (nil, false)
        }
        try? data.write(to: URL(fileURLWithPath: Self.tempPath))
        return (Self.tempPath, true)
    }

    /// Check if the screen has changed since the last `getLatestFrameBase64` call.
    func hasChanged() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return frameHash != lastSentHash
    }

    // MARK: - On-Demand Window Capture

    /// Capture a specific window by PID and return a base64-encoded JPEG.
    /// Uses SCScreenshotManager on macOS 14+, falls back to CGWindowListCreateImage.
    func captureWindow(pid: pid_t, quality: Double = 0.6) async throws -> String {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let window = content.windows.first(where: {
            $0.owningApplication?.processID == pid && $0.isOnScreen
        }) else {
            throw AIOSError.screenshotFailed(
                detail: "No on-screen window found for PID \(pid)"
            )
        }

        let cgImage: CGImage

        if #available(macOS 14.0, *) {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = 1280
            config.height = 800
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
        } else {
            // macOS 13 fallback: CGWindowListCreateImage
            let windowID = window.windowID
            let rect = window.frame
            guard let image = CGWindowListCreateImage(
                rect,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) else {
                throw AIOSError.screenshotFailed(
                    detail: "CGWindowListCreateImage failed for PID \(pid)"
                )
            }
            cgImage = image
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            throw AIOSError.screenshotFailed(
                detail: "Failed to encode window screenshot as JPEG"
            )
        }
        return data.base64EncodedString()
    }

    // MARK: - Vision OCR

    struct ScreenText {
        let text: String
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let confidence: Double
    }

    /// Run OCR on the latest frame using macOS Vision framework.
    /// Returns all text on screen with exact pixel coordinates.
    /// ~50-250ms on Apple Silicon depending on screen complexity.
    func extractTexts() -> (texts: [ScreenText], screenWidth: Int, screenHeight: Int, changed: Bool) {
        lock.lock()
        let frame = latestFrame
        let hash = frameHash
        let changed = hash != lastSentHash
        if changed { lastSentHash = hash }
        let screenW = actualScreenWidth
        let screenH = actualScreenHeight
        lock.unlock()

        guard let frame = frame else { return ([], 0, 0, false) }
        guard changed else { return ([], screenW, screenH, false) }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: frame)
        try? handler.perform([request])

        // Scale from capture coordinates to real screen coordinates
        let scaleX = Double(screenW) / Double(frame.width)
        let scaleY = Double(screenH) / Double(frame.height)

        let texts = (request.results ?? []).compactMap { observation -> ScreenText? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            // Vision returns normalized (0-1) coords, scale directly to real screen pixels
            return ScreenText(
                text: candidate.string,
                x: Int(box.origin.x * Double(screenW)),
                y: Int((1.0 - box.origin.y - box.height) * Double(screenH)),
                width: Int(box.width * Double(screenW)),
                height: Int(box.height * Double(screenH)),
                confidence: Double(round(candidate.confidence * 100) / 100)
            )
        }

        return (texts, screenW, screenH, true)
    }

    // MARK: - Frame Hashing

    /// FNV-1a hash sampling 16 points across the image for fast change detection.
    private func computeFrameHash(_ image: CGImage) -> UInt64 {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0 }

        let bytesPerRow = image.bytesPerRow
        let dataLength = CFDataGetLength(data)
        var hash: UInt64 = 14695981039346656037 // FNV-1a offset basis

        let samplePoints: [(Int, Int)] = [
            (width / 4, height / 4),
            (width / 2, height / 4),
            (3 * width / 4, height / 4),
            (width / 4, height / 2),
            (width / 2, height / 2),
            (3 * width / 4, height / 2),
            (width / 4, 3 * height / 4),
            (width / 2, 3 * height / 4),
            (3 * width / 4, 3 * height / 4),
            (width / 8, height / 8),
            (7 * width / 8, height / 8),
            (width / 8, 7 * height / 8),
            (7 * width / 8, 7 * height / 8),
            (width / 3, height / 3),
            (2 * width / 3, 2 * height / 3),
            (width / 2, height / 3),
        ]

        for (x, y) in samplePoints {
            let offset = y * bytesPerRow + x * 4
            if offset + 3 < dataLength {
                hash ^= UInt64(ptr[offset])
                hash &*= 1099511628211 // FNV-1a prime
                hash ^= UInt64(ptr[offset + 1])
                hash &*= 1099511628211
                hash ^= UInt64(ptr[offset + 2])
                hash &*= 1099511628211
            }
        }
        return hash
    }
}
