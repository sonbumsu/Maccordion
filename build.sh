#!/bin/zsh
# 사용법:
#   ./build.sh test          Core 자체 테스트
#   ./build.sh angle         뚜껑 각도 실시간 확인 (M1 도구)
#   ./build.sh angle --csv   각도를 CSV로 출력 (녹화용: ./build.sh angle --csv > samples.csv)
set -euo pipefail
cd "$(dirname "$0")"

TARGET="$(uname -m)-apple-macos14"
CORE=(Sources/Core/**/*.swift)
mkdir -p .build

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
    *)
        echo "사용법: ./build.sh test | angle [--csv]"
        echo "(앱 빌드는 M2에서 추가 예정)"
        exit 1
        ;;
esac
