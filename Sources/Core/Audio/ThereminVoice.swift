import Foundation

/// 테레민 소리를 한 샘플씩 합성한다. 오디오 스레드 전용 (할당·락 없음).
///
/// 목표 주파수와 음량은 바로 바꾸지 않고 짧게 보간해서 지퍼 노이즈와 클릭을 없앤다.
public struct ThereminVoice {
    public let sampleRate: Double
    /// 주파수가 목표의 63%까지 따라가는 시간(초).
    public var glideTime: Double = 0.010
    /// 음량이 목표의 63%까지 따라가는 시간(초).
    public var ampTime: Double = 0.005
    /// 비브라토 속도(Hz)와 깊이(반음).
    public var vibratoRate: Double = 5.5
    public var vibratoDepth: Double = 0.08

    public private(set) var frequency: Double
    public private(set) var amplitude: Double = 0

    private var phase: Double = 0
    private var vibratoPhase: Double = 0

    public init(sampleRate: Double, initialFrequency: Double = 440) {
        self.sampleRate = sampleRate
        self.frequency = initialFrequency
    }

    /// 버퍼를 채운다. 목표값은 버퍼 하나 동안 고정으로 본다.
    public mutating func render(into buffer: UnsafeMutablePointer<Float>, count: Int, targetFrequency: Double, targetAmplitude: Double) {
        let fCoef = 1 - exp(-1 / (glideTime * sampleRate))
        let aCoef = 1 - exp(-1 / (ampTime * sampleRate))
        let twoPi = 2 * Double.pi
        let vibStep = twoPi * vibratoRate / sampleRate

        for i in 0..<count {
            // 로그 영역에서 보간해야 높은 음/낮은 음 모두 같은 속도로 미끄러진다.
            frequency *= pow(targetFrequency / frequency, fCoef)
            amplitude += (targetAmplitude - amplitude) * aCoef

            let vib = vibratoDepth > 0 ? pow(2, vibratoDepth * sin(vibratoPhase) / 12) : 1
            vibratoPhase += vibStep
            if vibratoPhase > twoPi { vibratoPhase -= twoPi }

            buffer[i] = Float(sin(phase) * amplitude)
            phase += twoPi * frequency * vib / sampleRate
            if phase > twoPi { phase -= twoPi }
        }
    }
}
