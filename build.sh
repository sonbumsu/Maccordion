#!/bin/zsh
# 사용법:
#   ./build.sh               앱 빌드 (build/Maccordion.app)
#   ./build.sh run           빌드 후 실행
#   ./build.sh test          Core 자체 테스트
#   ./build.sh logo          Resources/LogoSource.png → Logo.png(투명 배경) → AppIcon.icns
#   ./build.sh angle         뚜껑 각도 실시간 확인 (M1 도구)
#   ./build.sh angle --csv   각도를 CSV로 출력 (녹화용: ./build.sh angle --csv > samples.csv)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-app.maccordion.mac}"
TARGET="$(uname -m)-apple-macos14"
CORE=(Sources/Core/**/*.swift)
APP=build/Maccordion.app
mkdir -p .build

build_app() {
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    swiftc -O -target "$TARGET" -module-name Maccordion $CORE Sources/App/*.swift -o "$APP/Contents/MacOS/Maccordion"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Maccordion</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>맥코디언</string>
    <key>CFBundleDisplayName</key><string>맥코디언</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
    xattr -cr "$APP"
    codesign --force --sign - "$APP" >/dev/null
    echo "빌드 완료: $APP"
}

make_logo() {
    swiftc -O Tools/remove_background.swift -o .build/remove_background
    swiftc -O Tools/make_icon.swift -o .build/make_icon
    .build/remove_background Resources/LogoSource.png Resources/Logo.png
    .build/make_icon Resources/Logo.png .build/icon_1024.png
    local set=.build/AppIcon.iconset
    rm -rf $set && mkdir -p $set
    for s in 16 32 128 256 512; do
        sips -z $s $s .build/icon_1024.png --out $set/icon_${s}x${s}.png >/dev/null
        sips -z $((s * 2)) $((s * 2)) .build/icon_1024.png --out $set/icon_${s}x${s}@2x.png >/dev/null
    done
    iconutil -c icns $set -o Resources/AppIcon.icns
    echo "로고 완료: Resources/Logo.png, Resources/AppIcon.icns"
}

case "${1:-}" in
    logo)
        make_logo
        ;;
    test)
        swiftc -O -target "$TARGET" $CORE Tests/main.swift -o .build/selftest
        exec .build/selftest
        ;;
    angle)
        swiftc -O -target "$TARGET" $CORE Sources/Tools/lidangle/main.swift -o .build/lidangle
        shift
        exec .build/lidangle "$@"
        ;;
    run)
        build_app
        open "$APP"
        ;;
    "")
        build_app
        ;;
    *)
        echo "사용법: ./build.sh [run | test | logo | angle [--csv]]"
        exit 1
        ;;
esac
