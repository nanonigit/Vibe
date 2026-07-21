#!/bin/bash
set -e
echo "Generating Xcode project..."
xcodegen generate

echo "Building Release version..."
xcodebuild -scheme MassiveMusic -configuration Release -derivedDataPath build/DerivedData build

echo "Restarting application..."
killall Vibe 2>/dev/null || true
open build/DerivedData/Build/Products/Release/Vibe.app

echo "Done!"
