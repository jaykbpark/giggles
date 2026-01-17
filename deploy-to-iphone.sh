#!/bin/bash

# Build and deploy to connected iPhone
# Usage: ./deploy-to-iphone.sh

set -e

cd frontend

echo "🔍 Checking for connected devices..."
DEVICE_OUTPUT=$(xcrun xcodebuild -showdestinations -project nw2025.xcodeproj -scheme nw2025 2>&1 | grep -E "platform:iOS.*arch:arm64.*id:[0-9A-F-]+.*name:" | grep -v "Simulator" | head -1)

if [ -z "$DEVICE_OUTPUT" ]; then
    echo "❌ No iPhone detected. Please connect your iPhone via USB."
    echo "💡 Make sure Developer Mode is enabled: Settings → Privacy & Security → Developer Mode"
    exit 1
fi

DEVICE_ID=$(echo "$DEVICE_OUTPUT" | grep -oE "id:[0-9A-F-]+" | cut -d: -f2)
DEVICE_NAME=$(echo "$DEVICE_OUTPUT" | grep -oE "name:[^,}]+" | cut -d: -f2)

echo "📱 Found device: $DEVICE_NAME ($DEVICE_ID)"
echo "🔨 Building and installing to device..."
echo ""

if xcodebuild \
    -project nw2025.xcodeproj \
    -scheme nw2025 \
    -destination "id=$DEVICE_ID" \
    -configuration Debug \
    build \
    install 2>&1 | tee /tmp/xcodebuild.log; then
    echo ""
    echo "✅ Build complete! Check your iPhone for the app."
else
    echo ""
    echo "❌ Build failed!"
    if grep -q "requires a development team" /tmp/xcodebuild.log; then
        echo ""
        echo "💡 Code signing setup required:"
        echo "   1. Open frontend/nw2025.xcodeproj in Xcode"
        echo "   2. Select project → 'nw2025' target → Signing & Capabilities"
        echo "   3. Check 'Automatically manage signing'"
        echo "   4. Select your Team (sign in with Apple ID if needed)"
        echo "   5. Run this script again"
    fi
    exit 1
fi
