#!/bin/bash
set -e
echo "Generating Xcode project..."
xcodegen generate

echo "Building Release version..."
xcodebuild -scheme MassiveMusic -configuration Release -derivedDataPath build/DerivedData build

echo "Updating /Applications/Vibe.app..."
killall Vibe 2>/dev/null || true
rm -rf /Applications/Vibe.app
cp -R build/DerivedData/Build/Products/Release/Vibe.app /Applications/Vibe.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Vibe.app

echo "Restarting application..."
open /Applications/Vibe.app

echo "Done!"
