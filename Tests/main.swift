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

// MARK: - PitchMapper / Note

test("각도 범위 양 끝이 C4, C6") {
    let m = PitchMapper()
    check(abs(m.frequency(for: 30) - 261.63) < 0.01, "30° = C4")
    check(abs(m.frequency(for: 130) - 1046.50) < 0.01, "130° = C6")
}

test("범위 밖은 양 끝으로 고정") {
    let m = PitchMapper()
    check(m.frequency(for: 10) == m.frequency(for: 30), "하한 아래는 C4")
    check(m.frequency(for: 170) == m.frequency(for: 130), "상한 위는 C6")
}

test("로그 스케일: 가운데 각도가 한 옥타브 위") {
    let m = PitchMapper()
    check(abs(m.frequency(for: 80) - 523.25) < 0.01, "80° = C5")
}

test("반음당 각도") {
    check(abs(PitchMapper().degreesPerSemitone - 100.0 / 24) < 1e-9, "100° / 24반음")
}

test("하한 아래는 연주 불가") {
    let m = PitchMapper()
    check(!m.isPlayable(29.9), "29.9°는 불가")
    check(m.isPlayable(30), "30°는 가능")
}

test("음이름과 센트") {
    let a = Note.nearest(to: 440)
    check(a.name == "A4" && abs(a.cents) < 1e-9, "440Hz = A4 +0")
    let c = Note.nearest(to: 261.6256)
    check(c.name == "C4", "261.63Hz = C4, 실제 \(c.name)")
    let sharp = Note.nearest(to: 440 * pow(2, 0.2 / 12))
    check(sharp.name == "A4" && abs(sharp.cents - 20) < 1e-6, "A4 +20센트, 실제 \(sharp)")
}

// MARK: - ThereminVoice

/// 양의 방향 영교차 수로 주파수를 추정한다.
func estimateFrequency(_ samples: [Float], sampleRate: Double) -> Double {
    var crossings = 0
    for i in 1..<samples.count where samples[i - 1] < 0 && samples[i] >= 0 { crossings += 1 }
    return Double(crossings) * sampleRate / Double(samples.count)
}

func renderVoice(_ voice: inout ThereminVoice, seconds: Double, freq: Double, amp: Double) -> [Float] {
    var out = [Float](repeating: 0, count: Int(seconds * voice.sampleRate))
    out.withUnsafeMutableBufferPointer { buf in
        var offset = 0
        while offset < buf.count {
            let n = min(512, buf.count - offset)
            voice.render(into: buf.baseAddress! + offset, count: n, targetFrequency: freq, targetAmplitude: amp)
            offset += n
        }
    }
    return out
}

test("목표 주파수로 소리를 냄") {
    var v = ThereminVoice(sampleRate: 48_000, initialFrequency: 440)
    v.vibratoDepth = 0
    _ = renderVoice(&v, seconds: 0.1, freq: 523.25, amp: 0.5)   // 글라이드 끝내기
    let out = renderVoice(&v, seconds: 1, freq: 523.25, amp: 0.5)
    let f = estimateFrequency(out, sampleRate: 48_000)
    check(abs(f - 523.25) < 2, "약 523Hz여야 함, 실제 \(f)")
    let peak = out.map { abs($0) }.max()!
    check(abs(peak - 0.5) < 0.01, "최대 진폭 0.5, 실제 \(peak)")
}

test("음량 0이면 무음") {
    var v = ThereminVoice(sampleRate: 48_000)
    let out = renderVoice(&v, seconds: 0.1, freq: 440, amp: 0)
    check(out.allSatisfy { $0 == 0 }, "전부 0이어야 함")
}

test("음량이 갑자기 바뀌어도 클릭 없음") {
    var v = ThereminVoice(sampleRate: 48_000)
    v.vibratoDepth = 0
    let out = renderVoice(&v, seconds: 0.05, freq: 440, amp: 1)
    // 440Hz 사인의 최대 기울기는 2π·440/48000 ≈ 0.058. 계단처럼 튀면 이보다 훨씬 크다.
    var maxStep: Float = 0
    for i in 1..<out.count { maxStep = max(maxStep, abs(out[i] - out[i - 1])) }
    check(maxStep < 0.07, "샘플 간 변화가 작아야 함, 실제 \(maxStep)")
}

test("주파수는 미끄러지듯 따라감") {
    var v = ThereminVoice(sampleRate: 48_000, initialFrequency: 261.63)
    _ = renderVoice(&v, seconds: 0.002, freq: 1046.5, amp: 0.5)
    check(v.frequency > 261.63 && v.frequency < 1046.5, "2ms 뒤엔 중간값, 실제 \(v.frequency)")
    _ = renderVoice(&v, seconds: 0.1, freq: 1046.5, amp: 0.5)
    check(abs(v.frequency - 1046.5) < 0.5, "100ms 뒤엔 도착, 실제 \(v.frequency)")
}

// MARK: - Bellows

/// 일정한 속도(°/s)로 seconds 동안 뚜껑을 움직인다. 센서처럼 정수 각도로 넣는다.
func moveBellows(_ b: inout Bellows, from start: Double, speed: Double, seconds: Double, t0: Double = 0) -> Double {
    var p = 0.0
    for i in 0...Int(seconds * 120) {
        let t = Double(i) / 120
        p = b.update(angle: (start + speed * t).rounded(), at: t0 + t)
    }
    return p
}

test("뚜껑을 가만히 두면 바람 없음") {
    var b = Bellows()
    let p = moveBellows(&b, from: 100, speed: 0, seconds: 1)
    check(p == 0, "정지 압력 0, 실제 \(p)")
    check(b.direction == .still, "정지 방향")
}

test("천천히 열면 약한 바람, 빨리 열면 센 바람") {
    var slow = Bellows(), fast = Bellows()
    let ps = moveBellows(&slow, from: 60, speed: 15, seconds: 0.8)
    let pf = moveBellows(&fast, from: 60, speed: 70, seconds: 0.8)
    check(ps > 0 && ps < pf, "느림 \(ps) < 빠름 \(pf)")
    check(pf > 0.7, "70°/s면 거의 최대, 실제 \(pf)")
}

test("여는 방향과 닫는 방향 모두 바람이 남") {
    var o = Bellows(), c = Bellows()
    let po = moveBellows(&o, from: 60, speed: 40, seconds: 0.5)
    let pc = moveBellows(&c, from: 120, speed: -40, seconds: 0.5)
    check(po > 0.3 && pc > 0.3, "열기 \(po), 닫기 \(pc)")
    check(o.direction == .opening && c.direction == .closing, "방향 구분")
}

test("멈추면 바람이 빨리 멈춤") {
    var b = Bellows()
    _ = moveBellows(&b, from: 60, speed: 50, seconds: 0.5)
    // 85°에서 멈춤
    var p = 1.0
    for i in 1...36 { p = b.update(angle: 85, at: 0.5 + Double(i) / 120) }   // 300ms
    check(p == 0, "멈추고 300ms 안에 0, 실제 \(p)")
}

// MARK: - AccordionKeyboard / HeldNotes

test("가운데 줄 A = C4, K = C5") {
    let kb = AccordionKeyboard()
    check(kb.key(for: 0)?.notes.first?.midi == 60, "A = 60")
    check(kb.key(for: 40)?.notes.first?.midi == 72, "K = 72")
    check(kb.key(for: 13)?.notes.first?.midi == 61, "W = C#4")
}

test("옥타브 이동") {
    var kb = AccordionKeyboard()
    kb.octaveShift = -1
    check(kb.key(for: 0)?.notes.first?.midi == 48, "A = C3")
}

test("화음 키: C 장조, A 단조") {
    let kb = AccordionKeyboard()
    let c = kb.key(for: 6)!.notes.map(\.midi)
    check(c == [36, 48, 52, 55], "Z = C2 + C3 E3 G3, 실제 \(c)")
    let am = kb.key(for: 9)!.notes.map(\.midi)
    check(am == [45, 57, 60, 64], "V = A2 + A3 C4 E4, 실제 \(am)")
}

test("모르는 키는 nil") {
    check(AccordionKeyboard().key(for: 49) == nil, "스페이스는 건반 아님")
}

test("같은 음을 두 키가 누르면 하나를 떼도 유지") {
    let kb = AccordionKeyboard()
    var h = HeldNotes()
    h.press(kb.key(for: 6)!)          // C 화음: C4 없음
    h.press(kb.key(for: 9)!)          // Am 화음: C4(60) 포함
    h.press(kb.key(for: 0)!)          // 멜로디 C4(60) 크기 1.0
    check(h.levels[60] == 1.0, "큰 쪽(1.0)")
    h.release(keyCode: 0)
    check(h.levels[60] == 0.35, "멜로디를 떼도 Am의 C4는 남음, 실제 \(String(describing: h.levels[60]))")
    h.release(keyCode: 9)
    check(h.levels[60] == nil, "다 떼면 없음")
}

test("키 반복은 새로 누른 게 아님") {
    var h = HeldNotes()
    let k = AccordionKeyboard().key(for: 0)!
    check(h.press(k), "처음은 true")
    check(!h.press(k), "반복은 false")
}

// MARK: - AccordionSynth

func renderAccordion(_ s: AccordionSynth, seconds: Double, gates: [Int: Double], pressure: Double) -> [Float] {
    var g = [Double](repeating: 0, count: AccordionSynth.noteCount)
    for (k, v) in gates { g[k] = v }
    var out = [Float](repeating: 0, count: Int(seconds * s.sampleRate))
    g.withUnsafeBufferPointer { gp in
        out.withUnsafeMutableBufferPointer { buf in
            var offset = 0
            while offset < buf.count {
                let n = min(512, buf.count - offset)
                s.render(into: buf.baseAddress! + offset, count: n, gates: gp.baseAddress!, targetPressure: pressure)
                offset += n
            }
        }
    }
    return out
}

/// 자기상관이 가장 큰 주기로 기본 주파수를 추정한다.
func autocorrelationPitch(_ x: [Float], sampleRate: Double, minHz: Double, maxHz: Double) -> Double {
    let minLag = Int(sampleRate / maxHz), maxLag = Int(sampleRate / minHz)
    var bestLag = minLag, best = -Double.infinity
    for lag in minLag...maxLag {
        var sum = 0.0
        for i in 0..<(x.count - lag) { sum += Double(x[i] * x[i + lag]) }
        sum /= Double(x.count - lag)
        if sum > best { best = sum; bestLag = lag }
    }
    return sampleRate / Double(bestLag)
}

func rms(_ x: ArraySlice<Float>) -> Double {
    sqrt(x.reduce(0) { $0 + Double($1 * $1) } / Double(x.count))
}

test("건반만 누르고 바람이 없으면 무음") {
    let s = AccordionSynth(sampleRate: 48_000)
    let out = renderAccordion(s, seconds: 0.2, gates: [60: 1], pressure: 0)
    check(out.allSatisfy { $0 == 0 }, "전부 0")
}

test("바람만 있고 건반이 없으면 무음") {
    let s = AccordionSynth(sampleRate: 48_000)
    let out = renderAccordion(s, seconds: 0.2, gates: [:], pressure: 1)
    check(out.allSatisfy { $0 == 0 }, "전부 0")
}

test("건반 + 바람이면 그 음 높이로 소리") {
    let s = AccordionSynth(sampleRate: 48_000)
    let out = renderAccordion(s, seconds: 1, gates: [69: 1], pressure: 0.8)   // A4
    let r = rms(out[4800...])
    check(r > 0.02, "소리가 나야 함, RMS \(r)")
    // 톱니파는 배음이 강해 영교차가 여러 번 생기므로 자기상관으로 잰다.
    let f = autocorrelationPitch(Array(out[4800..<(4800 + 4096)]), sampleRate: 48_000, minHz: 100, maxHz: 1000)
    check(abs(f - 440) < 15, "약 440Hz, 실제 \(f)")
}

test("바람이 셀수록 소리가 큼") {
    let weak = renderAccordion(AccordionSynth(sampleRate: 48_000), seconds: 0.5, gates: [60: 1], pressure: 0.2)
    let strong = renderAccordion(AccordionSynth(sampleRate: 48_000), seconds: 0.5, gates: [60: 1], pressure: 1)
    check(rms(strong[4800...]) > rms(weak[4800...]) * 2, "센 바람이 2배 넘게 큼")
}

test("화음을 꽉 눌러도 찢어지지 않음") {
    let s = AccordionSynth(sampleRate: 48_000)
    var gates: [Int: Double] = [:]
    for m in 36...84 { gates[m] = 1 }   // 49음 동시
    let out = renderAccordion(s, seconds: 0.3, gates: gates, pressure: 1)
    check(out.allSatisfy { $0.isFinite && abs($0) <= 0.5 }, "NaN 없고 0.5 이하")
}

test("건반을 떼면 곧 조용해짐") {
    let s = AccordionSynth(sampleRate: 48_000)
    _ = renderAccordion(s, seconds: 0.2, gates: [60: 1], pressure: 1)
    let tail = renderAccordion(s, seconds: 0.3, gates: [:], pressure: 1)
    check(rms(tail[9600...]) < 1e-3, "200ms 뒤 거의 무음")
    check(s.activeVoiceCount == 0, "남은 음성 0, 실제 \(s.activeVoiceCount)")
}

print("\n\(passed)개 통과, \(failures)개 실패")
exit(failures == 0 ? 0 : 1)
