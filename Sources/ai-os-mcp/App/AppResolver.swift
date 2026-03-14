import AppKit
import Foundation

final class AppResolver: @unchecked Sendable {

    /// List all GUI (regular activation policy) running apps.
    func listRunningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let name = app.localizedName else { return nil }
                return AppInfo(
                    name: name,
                    pid: app.processIdentifier,
                    bundleId: app.bundleIdentifier,
                    isActive: app.isActive
                )
            }
    }

    /// Get the frontmost (active) app.
    func frontmostApp() -> AppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let name = app.localizedName else { return nil }
        return AppInfo(
            name: name,
            pid: app.processIdentifier,
            bundleId: app.bundleIdentifier,
            isActive: true
        )
    }

    /// Resolve an app name to a PID. Case-insensitive, partial match.
    /// Prefers exact match, then frontmost, then first result.
    func resolve(appName: String) throws -> (pid: pid_t, name: String) {
        let query = appName.lowercased()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var matches: [(pid: pid_t, name: String, isActive: Bool)] = []

        for app in apps {
            guard let name = app.localizedName else { continue }
            if name.lowercased() == query || name.lowercased().contains(query) {
                matches.append((app.processIdentifier, name, app.isActive))
            }
        }

        if matches.isEmpty {
            let available = apps.compactMap { $0.localizedName }
            throw AIOSError.appNotFound(name: appName, available: available)
        }

        // Prefer exact match, then frontmost, then first
        if let exact = matches.first(where: { $0.name.lowercased() == query }) {
            return (exact.pid, exact.name)
        }
        if let active = matches.first(where: { $0.isActive }) {
            return (active.pid, active.name)
        }
        return (matches[0].pid, matches[0].name)
    }
}
