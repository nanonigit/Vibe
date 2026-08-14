#!/bin/bash
set -e
echo "Generating Xcode project..."
xcodegen generate

mkdir -p build
touch build/.metadata_never_index

echo "Building Release version..."
xcodebuild -scheme MassiveMusic -configuration Release -derivedDataPath build/DerivedData build

echo "Updating /Applications/Vibe.app..."
killall Vibe 2>/dev/null || true
rm -rf /Applications/Vibe.app
cp -R build/DerivedData/Build/Products/Release/Vibe.app /Applications/Vibe.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Vibe.app

# 中間成果物がランチャーに登録されるのを防ぐ
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u build/DerivedData/Build/Products/Release/Vibe.app 2>/dev/null || true
rm -rf build/DerivedData/Build/Products/Release/Vibe.app 2>/dev/null || true

echo "Restarting application..."
open /Applications/Vibe.app

echo "Done!"
