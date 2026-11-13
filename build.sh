#!/bin/zsh
# 사용법:
#   ./build.sh               앱 빌드 (build/LidTheremin.app)
#   ./build.sh run           빌드 후 실행
#   ./build.sh test          Core 자체 테스트
#   ./build.sh angle         뚜껑 각도 실시간 확인 (M1 도구)
#   ./build.sh angle --csv   각도를 CSV로 출력 (녹화용: ./build.sh angle --csv > samples.csv)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-app.lidtheremin.mac}"
TARGET="$(uname -m)-apple-macos14"
CORE=(Sources/Core/**/*.swift)
APP=build/LidTheremin.app
mkdir -p .build

build_app() {
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    swiftc -O -target "$TARGET" -module-name LidTheremin $CORE Sources/App/*.swift -o "$APP/Contents/MacOS/LidTheremin"
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>LidTheremin</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>뚜껑 테레민</string>
    <key>CFBundleDisplayName</key><string>뚜껑 테레민</string>
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

case "${1:-}" in
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
        echo "사용법: ./build.sh [run | test | angle [--csv]]"
        exit 1
        ;;
esac
