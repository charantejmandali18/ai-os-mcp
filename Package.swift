// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ai-os-mcp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .executableTarget(
            name: "ai-os-mcp",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "ai-os-mcpTests",
            dependencies: ["ai-os-mcp"]
        ),
    ]
)
