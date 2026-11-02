#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
bundle="dist/Pulse.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp .build/release/Pulse "$bundle/Contents/MacOS/Pulse"
cp Info.plist "$bundle/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/"
if [[ -f Assets/Pulse.icns ]]; then
    cp Assets/Pulse.icns "$bundle/Contents/Resources/Pulse.icns"
fi
codesign --force --deep --sign - "$bundle"
echo "Built: $PWD/$bundle"
