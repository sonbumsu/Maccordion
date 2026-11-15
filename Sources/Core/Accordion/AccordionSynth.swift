import Foundation

/// 아코디언 리드 소리를 128개 MIDI 노트에 대해 폴리포닉으로 합성한다. 오디오 스레드 전용.
///
/// - 노트마다 리드 2개: 기본음 + 살짝 높게 맞춘 리드(뮈제트). 둘이 맥놀이를 내서 아코디언 특유의 떨림이 난다.
/// - 리드 파형은 PolyBLEP 톱니파 (앨리어싱 줄임) → 1차 로우패스.
/// - 바람(압력)이 셀수록 소리가 커지고 밝아진다.
/// - 메모리는 init에서 다 잡아두고 render 중에는 할당하지 않는다.
public final class AccordionSynth {
    public static let noteCount = 128

    public let sampleRate: Double
    /// 두 번째 리드를 얼마나 높게 맞출지(센트).
    public var musetteCents: Double = 12
    /// 건반 누를 때/뗄 때 시간(초). 바람이 이미 들어가 있으므로 리드가 빨리 울리고 빨리 멈춘다.
    public var attackTime: Double = 0.008
    public var releaseTime: Double = 0.040
    /// 바람 변화 보간 시간(초).
    public var pressureTime: Double = 0.010
    /// 전체 음량. 여러 음을 동시에 내므로 작게 잡고 마지막에 소프트 클리핑한다.
    public var masterGain: Double = 0.22

    private let env: UnsafeMutablePointer<Double>
    private let phaseA: UnsafeMutablePointer<Double>
    private let phaseB: UnsafeMutablePointer<Double>
    private let lowpass: UnsafeMutablePointer<Double>
    private let baseFreq: UnsafeMutablePointer<Double>
    private var pressure: Double = 0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let n = Self.noteCount
        env = .allocate(capacity: n); env.initialize(repeating: 0, count: n)
        phaseA = .allocate(capacity: n); phaseA.initialize(repeating: 0, count: n)
        phaseB = .allocate(capacity: n); phaseB.initialize(repeating: 0, count: n)
        lowpass = .allocate(capacity: n); lowpass.initialize(repeating: 0, count: n)
        baseFreq = .allocate(capacity: n)
        for i in 0..<n {
            baseFreq[i] = 440 * pow(2, (Double(i) - 69) / 12)
            // 리드끼리 위상이 겹치지 않게 흩어둔다.
            phaseB[i] = Double((i * 7919) % 1000) / 1000
        }
    }

    deinit {
        env.deallocate(); phaseA.deallocate(); phaseB.deallocate()
        lowpass.deallocate(); baseFreq.deallocate()
    }

    /// 지금 소리가 나고 있는(감쇠 중 포함) 노트 수.
    public var activeVoiceCount: Int {
        (0..<Self.noteCount).filter { env[$0] > 0 }.count
    }

    /// - gates: 노트별 목표 크기 128개 (0이면 뗌)
    /// - targetPressure: 바람 0~1
    /// 결과를 buffer에 **덮어쓴다**.
    public func render(into buffer: UnsafeMutablePointer<Float>, count: Int,
                       gates: UnsafePointer<Double>, targetPressure: Double) {
        for i in 0..<count { buffer[i] = 0 }

        let attackCoef = 1 - exp(-1 / (attackTime * sampleRate))
        let releaseCoef = 1 - exp(-1 / (releaseTime * sampleRate))
        let pCoef = 1 - exp(-1 / (pressureTime * sampleRate))
        let detune = pow(2, musetteCents / 1200)

        // 바람은 모든 노트가 공유한다. 노트마다 같은 시작값에서 같은 식으로 보간하므로 결과가 같다.
        let startPressure = pressure

        for note in 0..<Self.noteCount {
            let gate = gates[note]
            var e = env[note]
            // 뗀 음이 -60dB 아래로 내려가면 끈다.
            if gate <= 0 && e < 1e-3 { env[note] = 0; continue }

            let f = baseFreq[note]
            let dtA = f / sampleRate
            let dtB = f * detune / sampleRate
            var pa = phaseA[note], pb = phaseB[note], lp = lowpass[note]
            var p = startPressure
            let coef = gate > e ? attackCoef : releaseCoef

            for i in 0..<count {
                p += (targetPressure - p) * pCoef
                e += (gate - e) * coef

                let reed = Self.polyBlepSaw(pa, dtA) + Self.polyBlepSaw(pb, dtB)
                pa += dtA; if pa >= 1 { pa -= 1 }
                pb += dtB; if pb >= 1 { pb -= 1 }

                // 바람이 셀수록 밝게: 차단 주파수 = 기본음의 2~10배 (최대 9kHz)
                let cutoff = min(f * (2 + 8 * p), 9000)
                let a = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
                lp += (reed * 0.5 - lp) * a

                buffer[i] += Float(lp * e * p)
            }
            env[note] = e
            phaseA[note] = pa
            phaseB[note] = pb
            lowpass[note] = lp
        }

        // 바람 상태 갱신 (노트가 하나도 없어도 진행)
        var p = startPressure
        for _ in 0..<count { p += (targetPressure - p) * pCoef }
        pressure = p

        // 여러 음이 겹쳐도 찢어지지 않게 부드럽게 눌러준다.
        let g = Float(masterGain)
        for i in 0..<count { buffer[i] = tanhf(buffer[i] * g * 2) * 0.5 }
    }

    /// 0~1 위상의 톱니파(-1~1)에 PolyBLEP 보정을 더한다.
    @inline(__always)
    static func polyBlepSaw(_ t: Double, _ dt: Double) -> Double {
        var v = 2 * t - 1
        if t < dt {
            let x = t / dt
            v -= x + x - x * x - 1
        } else if t > 1 - dt {
            let x = (t - 1) / dt
            v -= x * x + x + x + 1
        }
        return v
    }
}
