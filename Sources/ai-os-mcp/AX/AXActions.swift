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
