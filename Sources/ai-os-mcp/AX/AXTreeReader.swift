import ApplicationServices
import Foundation

final class AXTreeReader: @unchecked Sendable {

    private let operationTimeout: TimeInterval = 10.0

    /// Read the AX tree for an application PID.
    func readTree(
        pid: pid_t,
        maxDepth: Int = 5,
        maxChildren: Int = 50,
        filter: String? = nil
    ) -> AXNode? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 2.0)

        let deadline = Date().addingTimeInterval(operationTimeout)

        if let filter = filter, !filter.isEmpty {
            return readNodeFiltered(
                appElement,
                depth: 0,
                maxDepth: maxDepth + 3,
                maxChildren: maxChildren,
                filter: filter.lowercased(),
                deadline: deadline
            )
        } else {
            return readNode(
                appElement,
                depth: 0,
                maxDepth: maxDepth,
                maxChildren: maxChildren,
                deadline: deadline
            )
        }
    }

    // MARK: - Standard Tree Read

    private func readNode(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxChildren: Int,
        deadline: Date
    ) -> AXNode? {
        guard Date() < deadline else { return nil }
        guard depth <= maxDepth else { return nil }

        let role = axGetStringAttribute(element, kAXRoleAttribute) ?? "Unknown"
        var node = buildNode(element, role: role)

        if depth < maxDepth {
            let allChildren = axGetChildren(element)
            let truncated = allChildren.count > maxChildren
            let childSlice = allChildren.prefix(maxChildren)

            var childNodes: [AXNode] = []
            for child in childSlice {
                guard Date() < deadline else { break }
                if let childNode = readNode(
                    child,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    maxChildren: maxChildren,
                    deadline: deadline
                ) {
                    childNodes.append(childNode)
                }
            }

            if truncated {
                var placeholder = AXNode(role: "Truncated")
                placeholder.title = "... \(allChildren.count - maxChildren) more children"
                childNodes.append(placeholder)
            }

            if !childNodes.isEmpty {
                node.children = childNodes
            }
        }

        return node
    }

    // MARK: - Filtered Tree Read

    private func readNodeFiltered(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxChildren: Int,
        filter: String,
        deadline: Date
    ) -> AXNode? {
        guard Date() < deadline else { return nil }
        guard depth <= maxDepth else { return nil }

        let role = axGetStringAttribute(element, kAXRoleAttribute) ?? "Unknown"
        let node = buildNode(element, role: role)
        let matches = nodeMatchesFilter(node, filter: filter)

        let allChildren = axGetChildren(element)
        let childSlice = allChildren.prefix(maxChildren)

        var matchingChildren: [AXNode] = []
        for child in childSlice {
            guard Date() < deadline else { break }
            if let childNode = readNodeFiltered(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxChildren: maxChildren,
                filter: filter,
                deadline: deadline
            ) {
                matchingChildren.append(childNode)
            }
        }

        if matches || !matchingChildren.isEmpty {
            var result = node
            if !matchingChildren.isEmpty {
                result.children = matchingChildren
            }
            return result
        }

        return nil
    }

    // MARK: - Helpers

    private func nodeMatchesFilter(_ node: AXNode, filter: String) -> Bool {
        if let t = node.title, t.lowercased().contains(filter) { return true }
        if let id = node.identifier, id.lowercased().contains(filter) { return true }
        if let d = node.nodeDescription, d.lowercased().contains(filter) { return true }
        return false
    }

    private func buildNode(_ element: AXUIElement, role: String) -> AXNode {
        let title = axGetStringAttribute(element, kAXTitleAttribute)
        let rawValue = axGetAttribute(element, kAXValueAttribute)
        let value = rawValue.flatMap { axConvertValue($0) }
        let identifier = axGetStringAttribute(element, kAXIdentifierAttribute)
        let desc = axGetStringAttribute(element, kAXDescriptionAttribute)
        let roleDesc = axGetStringAttribute(element, kAXRoleDescriptionAttribute)
        let position = axGetPosition(element)
        let size = axGetSize(element)
        let actions = axGetActions(element)
        let enabled = axGetBoolAttribute(element, kAXEnabledAttribute)
        let focused = axGetBoolAttribute(element, kAXFocusedAttribute)
        let selected = axGetBoolAttribute(element, kAXSelectedAttribute)
        let expanded = axGetBoolAttribute(element, kAXExpandedAttribute)

        return AXNode(
            role: role,
            title: title,
            value: value,
            identifier: identifier,
            nodeDescription: desc,
            roleDescription: roleDesc,
            position: position,
            size: size,
            actions: actions.isEmpty ? nil : actions,
            enabled: enabled,
            focused: focused,
            selected: selected,
            expanded: expanded
        )
    }
}
