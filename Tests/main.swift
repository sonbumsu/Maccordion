import Foundation

// Core 자체 테스트. Xcode 없이 ./build.sh test 로 돌린다.

var failures = 0
var passed = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failures += 1
        print("  ✗ \(message) (Tests/main.swift:\(line))")
    }
}

func test(_ name: String, _ body: () -> Void) {
    let before = failures
    body()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

// MARK: - OneEuroFilter

test("첫 샘플은 그대로 통과") {
    var f = OneEuroFilter()
    check(f.filter(90, at: 0) == 90, "첫 출력이 90이어야 함")
}

test("일정한 입력에 수렴") {
    var f = OneEuroFilter()
    _ = f.filter(90, at: 0)
    var out = 0.0
    for i in 1...240 { out = f.filter(100, at: Double(i) / 120) }
    check(abs(out - 100) < 0.1, "2초 뒤 100°에 수렴해야 함, 실제 \(out)")
}

test("1° 정수 떨림을 부드럽게") {
    var f = OneEuroFilter()
    var outputs: [Double] = []
    for i in 0..<240 { outputs.append(f.filter(i % 2 == 0 ? 90 : 91, at: Double(i) / 120)) }
    let tail = outputs.suffix(60)
    let spread = tail.max()! - tail.min()!
    check(spread < 0.5, "떨림 폭이 0.5° 미만이어야 함, 실제 \(spread)")
}

test("빠른 움직임에서 고정 필터보다 덜 늦음") {
    var adaptive = OneEuroFilter(minCutoff: 1, beta: 0.05)
    var fixed = OneEuroFilter(minCutoff: 1, beta: 0)
    var a = 0.0, b = 0.0
    for i in 0...60 {
        let t = Double(i) / 120, v = 40 + 180 * t
        a = adaptive.filter(v, at: t)
        b = fixed.filter(v, at: t)
    }
    let target = 40 + 180 * 0.5
    check(abs(target - a) < abs(target - b), "적응형 오차 \(abs(target - a)) < 고정 오차 \(abs(target - b))")
}

test("각속도 부호") {
    var f = OneEuroFilter()
    for i in 0...120 { _ = f.filter(40 + Double(i) * 0.5, at: Double(i) / 120) }
    check(f.velocity > 0, "여는 중이면 속도가 양수여야 함, 실제 \(f.velocity)")
}

test("시간이 그대로면 무시") {
    var f = OneEuroFilter()
    _ = f.filter(90, at: 1)
    check(f.filter(120, at: 1) == 90, "같은 타임스탬프는 이전 값 유지")
}

// MARK: - AngleSmoother

test("한 번 튀는 값은 버림") {
    var s = AngleSmoother()
    _ = s.process(90, at: 0)
    check(s.process(170, at: 0.01) == nil, "튄 값은 nil")
    check(s.process(90, at: 0.02) != nil, "정상 값은 통과")
}

test("계속 벗어나면 진짜 움직임으로 인정") {
    var s = AngleSmoother(outlierAcceptCount: 3)
    _ = s.process(90, at: 0)
    check(s.process(130, at: 0.01) == nil, "1번째 거부")
    check(s.process(130, at: 0.02) == nil, "2번째 거부")
    check(s.process(130, at: 0.03) == 130, "3번째 수락 후 필터 재시작")
}

print("\n\(passed)개 통과, \(failures)개 실패")
exit(failures == 0 ? 0 : 1)
