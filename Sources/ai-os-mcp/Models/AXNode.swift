import Foundation

struct AXNode: Codable, Sendable {
    let role: String
    var title: String?
    var value: AXNodeValue?
    var identifier: String?
    var nodeDescription: String?
    var roleDescription: String?
    var position: AXPoint?
    var size: AXSize?
    var actions: [String]?
    var enabled: Bool?
    var focused: Bool?
    var selected: Bool?
    var expanded: Bool?
    var children: [AXNode]?

    struct AXPoint: Codable, Sendable {
        let x: Double
        let y: Double
    }

    struct AXSize: Codable, Sendable {
        let width: Double
        let height: Double
    }

    enum CodingKeys: String, CodingKey {
        case role, title, value, identifier
        case nodeDescription = "description"
        case roleDescription, position, size, actions
        case enabled, focused, selected, expanded, children
    }
}

/// Wrapper to handle heterogeneous AX values in JSON.
enum AXNodeValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .string("")
        }
    }
}

extension AXNode {
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
