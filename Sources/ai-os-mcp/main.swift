import Foundation
import MCP

// MARK: - Stderr Output (stdout is reserved for MCP JSON-RPC)

nonisolated(unsafe) var standardError = FileHandle.standardError

extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}

func log(_ message: String) {
    print("[ai-os-mcp] \(message)", to: &standardError)
}

// MARK: - Main

log("Starting ai-os-mcp v0.1.0...")

// Check accessibility permission (with prompt on first run)
let trusted = axCheckPermission()
if !trusted {
    log("WARNING: Accessibility permission not granted.")
    log("  Open System Settings → Privacy & Security → Accessibility")
    log("  Add and enable this binary, then restart.")
    log("  Tools requiring AX access will return errors until permission is granted.")
}

// Create MCP server
let server = Server(
    name: "ai-os-mcp",
    version: "0.1.0",
    capabilities: Server.Capabilities(
        tools: .init(listChanged: false)
    )
)

// Register all tools
await registerTools(on: server)

log("MCP server ready. Listening on stdio...")

// Start stdio transport and block until connection closes
let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()

log("Server shut down.")
