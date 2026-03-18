import ApplicationServices
import AppKit
import Foundation

final class AXActions: @unchecked Sendable {

    // MARK: - App Management

    /// Bring an app's window to front.
    func raiseApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [])
        }
    }

    // MARK: - Element Actions

    /// Press (click) an AX element via AXPress, AXConfirm, or AXPick.
    func pressElement(_ element: AXUIElement) throws {
        let actions = axGetActions(element)

        let actionPriority = [
            kAXPressAction as String,
            kAXConfirmAction as String,
            kAXPickAction as String,
        ]

        for action in actionPriority {
            if actions.contains(action) {
                let result = AXUIElementPerformAction(element, action as CFString)
                if result == .success {
                    return
                }
                throw AIOSError.actionFailed(action: action, detail: axErrorDescription(result))
            }
        }

        throw AIOSError.actionFailed(
            action: "press",
            detail: "Element has no press/confirm/pick action. Available: \(actions)"
        )
    }

    /// Focus an AX element.
    func focusElement(_ element: AXUIElement) {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
    }

    /// Try setting a text value directly on an AX element.
    /// Returns true if successful.
    func setTextValue(_ element: AXUIElement, text: String) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, text as CFTypeRef
        )
        return result == .success
    }

    // MARK: - CGEvent Text Input

    /// Type text using CGEvent keystroke simulation with multi-character bursts.
    func typeTextViaCGEvent(_ text: String) {
        let chunkSize = 20
        let chars = Array(text.utf16)

        for i in stride(from: 0, to: chars.count, by: chunkSize) {
            let end = min(i + chunkSize, chars.count)
            let chunk = Array(chars[i..<end])

            if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            {
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
                usleep(10_000)  // 10ms between chunks
            }
        }
    }

    // MARK: - Key Press

    /// Press a key with optional modifiers using CGEvent.
    func pressKey(key: String, modifiers: [String]) throws {
        guard let keyCode = keyCodeFor(key) else {
            throw AIOSError.invalidArguments(
                detail: """
                    Unknown key: '\(key)'. Valid keys: return, escape, tab, space, delete, \
                    up, down, left, right, f1-f12, home, end, pageup, pagedown, \
                    or a single character.
                    """
            )
        }

        var flags = CGEventFlags()
        for mod in modifiers {
            switch mod.lowercased() {
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            default:
                throw AIOSError.invalidArguments(
                    detail: "Unknown modifier: '\(mod)'. Valid: command, shift, option, control"
                )
            }
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            throw AIOSError.actionFailed(action: "press_key", detail: "Failed to create CGEvent")
        }

        // For single character keys mapped to keyCode 0, set the unicode string
        if key.count == 1 && keyCode == 0 {
            let utf16 = Array(key.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Mouse Button Type

    enum MouseButton: String {
        case left, right, middle
    }

    enum ClickType: String {
        case single, double, triple
    }

    // MARK: - Mouse Click

    func mouseClick(x: Double, y: Double, button: MouseButton, clickType: ClickType) throws {
        let point = CGPoint(x: x, y: y)
        let (downType, upType, cgButton) = try mouseEventTypes(for: button)

        let clickCount: Int64
        switch clickType {
        case .single: clickCount = 1
        case .double: clickCount = 2
        case .triple: clickCount = 3
        }

        for i in 1...Int(clickCount) {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: cgButton),
                  let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: cgButton)
            else {
                throw AIOSError.actionFailed(action: "mouse_click", detail: "Failed to create CGEvent")
            }
            down.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(30_000) // 30ms between clicks
        }
    }

    private func mouseEventTypes(for button: MouseButton) throws -> (CGEventType, CGEventType, CGMouseButton) {
        switch button {
        case .left:
            return (.leftMouseDown, .leftMouseUp, .left)
        case .right:
            return (.rightMouseDown, .rightMouseUp, .right)
        case .middle:
            return (.otherMouseDown, .otherMouseUp, .center)
        }
    }

    // MARK: - Mouse Drag

    func mouseDrag(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double) throws {
        let from = CGPoint(x: fromX, y: fromY)
        let to = CGPoint(x: toX, y: toY)

        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left) else {
            throw AIOSError.actionFailed(action: "mouse_drag", detail: "Failed to create CGEvent")
        }
        down.post(tap: .cghidEventTap)

        // Smooth interpolation
        let steps = max(10, Int(duration * 60)) // ~60fps
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let x = fromX + (toX - fromX) * t
            let y = fromY + (toY - fromY) * t
            let point = CGPoint(x: x, y: y)
            if let move = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) {
                move.post(tap: .cghidEventTap)
            }
            usleep(UInt32(duration / Double(steps) * 1_000_000))
        }

        guard let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left) else {
            throw AIOSError.actionFailed(action: "mouse_drag", detail: "Failed to create mouse up event")
        }
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Scroll

    func scroll(direction: String, amount: Int, atX: Double, atY: Double) throws {
        // Move mouse to target position first
        let point = CGPoint(x: atX, y: atY)
        if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
            usleep(50_000) // 50ms for mouse to settle
        }

        let (deltaY, deltaX): (Int32, Int32)
        switch direction.lowercased() {
        case "up": (deltaY, deltaX) = (Int32(amount), 0)
        case "down": (deltaY, deltaX) = (Int32(-amount), 0)
        case "left": (deltaY, deltaX) = (0, Int32(amount))
        case "right": (deltaY, deltaX) = (0, Int32(-amount))
        default:
            throw AIOSError.invalidArguments(
                detail: "Invalid scroll direction: '\(direction)'. Valid: up, down, left, right"
            )
        }

        // Send scroll events in increments for smooth scrolling
        let perStepY = deltaY / Int32(amount)
        let perStepX = deltaX / Int32(amount)
        for _ in 0..<amount {
            let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                      wheelCount: 2, wheel1: perStepY,
                                      wheel2: perStepX, wheel3: 0)
            scrollEvent?.post(tap: .cghidEventTap)
            usleep(16_000) // ~60fps
        }
    }

    // MARK: - Key Code Mapping

    private func keyCodeFor(_ key: String) -> CGKeyCode? {
        let namedKeys: [String: CGKeyCode] = [
            "return": 0x24, "enter": 0x24,
            "tab": 0x30,
            "space": 0x31,
            "delete": 0x33, "backspace": 0x33,
            "escape": 0x35, "esc": 0x35,
            "left": 0x7B, "right": 0x7C,
            "down": 0x7D, "up": 0x7E,
            "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
            "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
            "home": 0x73, "end": 0x77,
            "pageup": 0x74, "pagedown": 0x79,
            "forwarddelete": 0x75,
        ]

        let lower = key.lowercased()
        if let code = namedKeys[lower] {
            return code
        }

        // Single character — map to macOS virtual key codes
        if key.count == 1 {
            let charMap: [Character: CGKeyCode] = [
                "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03,
                "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
                "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
                "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
                "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
                "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
                "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C,
                "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
                "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25,
                "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
                "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D,
                "m": 0x2E, ".": 0x2F, "`": 0x32,
            ]

            if let code = charMap[Character(lower)] {
                return code
            }

            // Fallback: keyCode 0 with unicode string (handled in pressKey)
            return 0
        }

        return nil
    }
}
