import ApplicationServices
import Foundation

// MARK: - Attribute Reading

func axGetAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return result == .success ? value : nil
}

func axGetStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    axGetAttribute(element, attribute) as? String
}

func axGetBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
    guard let value = axGetAttribute(element, attribute) else { return nil }
    if let boolVal = value as? Bool { return boolVal }
    if let numVal = value as? NSNumber { return numVal.boolValue }
    return nil
}

func axGetChildren(_ element: AXUIElement) -> [AXUIElement] {
    (axGetAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func axGetActions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    let result = AXUIElementCopyActionNames(element, &names)
    return result == .success ? (names as? [String] ?? []) : []
}

func axGetPosition(_ element: AXUIElement) -> AXNode.AXPoint? {
    guard let value = axGetAttribute(element, kAXPositionAttribute) else { return nil }
    var point = CGPoint.zero
    // swiftlint:disable:next force_cast
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return AXNode.AXPoint(x: Double(point.x), y: Double(point.y))
}

func axGetSize(_ element: AXUIElement) -> AXNode.AXSize? {
    guard let value = axGetAttribute(element, kAXSizeAttribute) else { return nil }
    var size = CGSize.zero
    // swiftlint:disable:next force_cast
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return AXNode.AXSize(width: Double(size.width), height: Double(size.height))
}

// MARK: - Value Conversion

func axConvertValue(_ raw: CFTypeRef) -> AXNodeValue? {
    if let s = raw as? String { return .string(s) }
    if let n = raw as? NSNumber {
        // NSNumber wraps both bools and numbers — check CFBoolean first
        if CFGetTypeID(n) == CFBooleanGetTypeID() {
            return .bool(n.boolValue)
        }
        return .number(n.doubleValue)
    }
    // For other types, stringify if meaningful
    let desc = "\(raw)"
    if !desc.isEmpty && !desc.hasPrefix("<AX") {
        return .string(desc)
    }
    return nil
}

// MARK: - Permission Check

func axCheckPermission() -> Bool {
    let key = "AXTrustedCheckOptionPrompt" as CFString
    let options = [key: kCFBooleanTrue!] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

/// Check permission without showing the system prompt.
func axCheckPermissionSilent() -> Bool {
    AXIsProcessTrusted()
}

// MARK: - Error Description

func axErrorDescription(_ error: AXError) -> String {
    switch error {
    case .success: return "success"
    case .failure: return "generic failure"
    case .illegalArgument: return "illegal argument"
    case .invalidUIElement: return "invalid UI element (stale reference)"
    case .invalidUIElementObserver: return "invalid observer"
    case .cannotComplete: return "cannot complete (app may be unresponsive)"
    case .attributeUnsupported: return "attribute unsupported"
    case .actionUnsupported: return "action unsupported"
    case .notificationUnsupported: return "notification unsupported"
    case .notImplemented: return "not implemented"
    case .notificationAlreadyRegistered: return "notification already registered"
    case .notificationNotRegistered: return "notification not registered"
    case .apiDisabled: return "accessibility API disabled"
    case .noValue: return "no value"
    case .parameterizedAttributeUnsupported: return "parameterized attribute unsupported"
    case .notEnoughPrecision: return "not enough precision"
    @unknown default: return "unknown error (\(error.rawValue))"
    }
}
