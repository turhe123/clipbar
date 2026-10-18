#!/usr/bin/env bash
# Builds ClipBar as a universal (arm64 + x86_64) release binary, assembles ClipBar.app,
# ad-hoc signs it, verifies the bundle and zips it to dist/ClipBar.zip.
#
# Usage: ./scripts/build_app.sh            # universal build
#        ARCHS="arm64" ./scripts/build_app.sh   # single-arch build
#
# Requires only the Xcode Command Line Tools. Prefers `swift build`; if the SwiftPM manifest
# toolchain is unusable on this machine it falls back to compiling the sources with swiftc directly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="ClipBar"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME.zip"
ARCHS="${ARCHS:-arm64 x86_64}"
SDK="$(xcrun --show-sdk-path)"
DEPLOYMENT_TARGET="14.0"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"

log() { printf '\033[1;35m▸\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Compile
# ---------------------------------------------------------------------------
BINARY=""
SPM_ARCH_FLAGS=()
for arch in $ARCHS; do SPM_ARCH_FLAGS+=(--arch "$arch"); done

log "Building $APP_NAME $VERSION ($ARCHS) in release mode"
if swift build -c release "${SPM_ARCH_FLAGS[@]}" 2>"$DIST.spm.log"; then
    BIN_DIR="$(swift build -c release "${SPM_ARCH_FLAGS[@]}" --show-bin-path)"
    BINARY="$BIN_DIR/$APP_NAME"
    log "swift build succeeded → $BINARY"
else
    log "swift build unavailable on this toolchain ($(grep -m1 -oE 'Invalid manifest|error: [^(]*' "$DIST.spm.log" || echo 'see dist.spm.log')); falling back to swiftc"
    mkdir -p "$ROOT/.build/direct"
    SOURCES=()
    while IFS= read -r file; do SOURCES+=("$file"); done < <(find Sources -name '*.swift' | sort)
    SLICES=()
    for arch in $ARCHS; do
        OUT="$ROOT/.build/direct/$APP_NAME-$arch"
        log "swiftc → $arch"
        swiftc -O -wmo -swift-version 5 \
            -target "$arch-apple-macos$DEPLOYMENT_TARGET" -sdk "$SDK" \
            -module-name "$APP_NAME" "${SOURCES[@]}" \
            -framework AppKit -framework SwiftUI -framework Carbon -framework ImageIO -framework ServiceManagement \
            -lsqlite3 -o "$OUT"
        SLICES+=("$OUT")
    done
    BINARY="$ROOT/.build/direct/$APP_NAME"
    if [ "${#SLICES[@]}" -gt 1 ]; then
        lipo -create "${SLICES[@]}" -output "$BINARY"
    else
        cp "${SLICES[0]}" "$BINARY"
    fi
fi
rm -f "$DIST.spm.log"

# ---------------------------------------------------------------------------
# 2. Assemble the bundle
# ---------------------------------------------------------------------------
log "Assembling $APP"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f Resources/AppIcon.icns ]; then
    log "Generating app icon"
    ICONSET="$ROOT/.build/AppIcon.iconset"
    rm -rf "$ICONSET"
    swift scripts/make_icon.swift "$ICONSET" docs/assets/icon.png 512
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# ---------------------------------------------------------------------------
# 3. Sign (ad-hoc) and verify
# ---------------------------------------------------------------------------
log "Signing (ad-hoc)"
xattr -cr "$APP"   # Finder metadata / quarantine bits would make codesign refuse the bundle
codesign --force --deep --sign - --timestamp=none "$APP"

log "Verifying bundle"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" = "true"
test -f "$APP/Contents/Resources/AppIcon.icns"

# ---------------------------------------------------------------------------
# 4. Zip
# ---------------------------------------------------------------------------
log "Zipping → $ZIP"
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
du -h "$ZIP" | awk '{print "   " $1 "\t" $2}'
log "Done. Launch with: open \"$APP\""
