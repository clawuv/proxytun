#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="3.2.0"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

APP_PATH="$SCRIPT_DIR/output/ProxyTun.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: ProxyTun.app not found in output directory"
    echo "Export the app from Xcode to output/ first"
    exit 1
fi

mkdir -p "$SCRIPT_DIR/build/component"

cp -R "$APP_PATH" "$SCRIPT_DIR/build/component/"

echo "Creating installer package..."

pkgbuild \
    --root build/component \
    --identifier com.proxytun.ProxyTun \
    --version 3.2.0 \
    --install-location /Applications \
    build/temp.pkg

cat > build/distribution.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>ProxyTun</title>
    <pkg-ref id="com.proxytun.ProxyTun"/>
    <options customize="never" require-scripts="false"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.proxytun.ProxyTun"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.proxytun.ProxyTun" visible="false">
        <pkg-ref id="com.proxytun.ProxyTun"/>
    </choice>
    <pkg-ref id="com.proxytun.ProxyTun" version="3.2.0" onConclusion="none">temp.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild \
    --distribution build/distribution.xml \
    --package-path build \
    output/ProxyTun-v$VERSION-Universal-Installer.pkg

echo "Package created: output/ProxyTun-v$VERSION-Universal-Installer.pkg"

if [ -n "$APPLE_ID" ] && [ -n "$APPLE_APP_PASSWORD" ] && [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing installer..."
    productsign --sign "$SIGNING_IDENTITY" \
        output/ProxyTun-v$VERSION-Universal-Installer.pkg \
        output/ProxyTun-v$VERSION-Universal-Installer-signed.pkg

    mv output/ProxyTun-v$VERSION-Universal-Installer-signed.pkg output/ProxyTun-v$VERSION-Universal-Installer.pkg

    echo "Notarizing installer..."
    xcrun notarytool submit output/ProxyTun-v$VERSION-Universal-Installer.pkg \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple output/ProxyTun-v$VERSION-Universal-Installer.pkg
    echo "Installer signed and notarized"
else
    echo "Skipping signing/notarization - set APPLE_ID, APPLE_APP_PASSWORD, SIGNING_IDENTITY, and TEAM_ID in .env"
fi

rm -rf build

echo "✓ Build complete"
echo "  App: output/ProxyTun.app"
echo "  PKG: output/ProxyTun-v$VERSION-Universal-Installer.pkg"
