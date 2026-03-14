#!/bin/bash
set -euo pipefail

BINARY_NAME="ai-os-mcp"
INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/Library/Application Support/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

echo "Building $BINARY_NAME (release)..."
swift build -c release

BUILT_BINARY=".build/release/$BINARY_NAME"
if [ ! -f "$BUILT_BINARY" ]; then
    echo "Build failed. Binary not found at $BUILT_BINARY"
    exit 1
fi

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp "$BUILT_BINARY" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"
echo "Installed: $BINARY_PATH"

# Configure Claude Desktop
echo ""
echo "Configuring Claude Desktop..."
mkdir -p "$CONFIG_DIR"

MCP_ENTRY="{\"command\":\"$BINARY_PATH\"}"

if [ -f "$CONFIG_FILE" ]; then
    if command -v jq &>/dev/null; then
        UPDATED=$(jq --argjson entry "$MCP_ENTRY" '.mcpServers["ai-os-mcp"] = $entry' "$CONFIG_FILE")
        echo "$UPDATED" > "$CONFIG_FILE"
        echo "Updated existing Claude Desktop config."
    else
        echo ""
        echo "jq not found. Please manually add this to $CONFIG_FILE:"
        echo ""
        echo "  \"mcpServers\": {"
        echo "    \"ai-os-mcp\": { \"command\": \"$BINARY_PATH\" }"
        echo "  }"
    fi
else
    cat > "$CONFIG_FILE" << ENDJSON
{
  "mcpServers": {
    "ai-os-mcp": {
      "command": "$BINARY_PATH"
    }
  }
}
ENDJSON
    echo "Created Claude Desktop config."
fi

echo ""
echo "Accessibility Permission Setup"
echo "  1. Open System Settings > Privacy & Security > Accessibility"
echo "  2. Click + and add: $BINARY_PATH"
echo "  3. Toggle it ON"
echo "  4. Restart Claude Desktop"
echo ""
echo "Done! Restart Claude Desktop to start using ai-os-mcp."
