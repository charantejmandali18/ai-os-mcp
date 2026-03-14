import Foundation

struct AppInfo: Codable, Sendable {
    let name: String
    let pid: Int32
    let bundleId: String?
    let isActive: Bool
}
