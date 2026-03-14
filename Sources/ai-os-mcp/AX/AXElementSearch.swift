import ApplicationServices
import Foundation

struct AXSearchResult: @unchecked Sendable {
    let element: AXUIElement
    let role: String
    let title: String?
    let identifier: String?
    let nodeDescription: String?
}

final class AXElementSearch: @unchecked Sendable {

    /// Search the AX tree for elements matching the query.
    /// Priority: exact title → exact id → exact desc → substring title → substring desc.
    /// Optionally filter by role. Results are in depth-first tree order within each priority.
    func search(
        root: AXUIElement,
        query: String,
        role: String? = nil,
        maxResults: Int = 20
    ) -> [AXSearchResult] {
        var exactTitle: [AXSearchResult] = []
        var exactId: [AXSearchResult] = []
        var exactDesc: [AXSearchResult] = []
        var substringTitle: [AXSearchResult] = []
        var substringDesc: [AXSearchResult] = []

        let lowerQuery = query.lowercased()

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 15 else { return }

            let r = axGetStringAttribute(element, kAXRoleAttribute) ?? ""
            let roleMatches = (role == nil) || (r == role)

            if roleMatches {
                let t = axGetStringAttribute(element, kAXTitleAttribute)
                let id = axGetStringAttribute(element, kAXIdentifierAttribute)
                let d = axGetStringAttribute(element, kAXDescriptionAttribute)

                let result = AXSearchResult(
                    element: element,
                    role: r,
                    title: t,
                    identifier: id,
                    nodeDescription: d
                )

                if let t = t, t == query {
                    exactTitle.append(result)
                } else if let id = id, id == query {
                    exactId.append(result)
                } else if let d = d, d == query {
                    exactDesc.append(result)
                } else if let t = t, t.lowercased().contains(lowerQuery) {
                    substringTitle.append(result)
                } else if let d = d, d.lowercased().contains(lowerQuery) {
                    substringDesc.append(result)
                }
            }

            // Always recurse — role filter only affects matching, not traversal
            let children = axGetChildren(element)
            for child in children {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)

        // Combine in priority order
        var results: [AXSearchResult] = []
        results.append(contentsOf: exactTitle)
        results.append(contentsOf: exactId)
        results.append(contentsOf: exactDesc)
        results.append(contentsOf: substringTitle)
        results.append(contentsOf: substringDesc)

        return Array(results.prefix(maxResults))
    }
}
