#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/.local/lib/ai-os-browser"

echo "Building ai-os-browser..."
cd "$SCRIPT_DIR"
npm install
npm run build

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -r dist/ "$INSTALL_DIR/dist/"
cp package.json "$INSTALL_DIR/"
cp -r node_modules/ "$INSTALL_DIR/node_modules/"

echo "ai-os-browser installed to $INSTALL_DIR"
echo ""
echo "Add to your Claude Code settings (~/.claude.json or .claude/settings.json):"
echo '  "mcpServers": {'
echo '    "ai-os-browser": {'
echo '      "command": "node",'
echo "      \"args\": [\"$INSTALL_DIR/dist/index.js\"]"
echo '    }'
echo '  }'
