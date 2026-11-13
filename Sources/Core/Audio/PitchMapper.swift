import Foundation

/// 뚜껑 각도(°)를 주파수(Hz)로 바꾼다.
/// 캘리브레이션 범위 안에서 로그 스케일로 매핑하므로, 같은 각도만큼 움직이면 같은 음정만큼 바뀐다.
public struct PitchMapper {
    /// 연주 가능한 가장 닫힌 각도. 이보다 닫으면 소리를 끈다.
    public var minAngle: Double
    /// 연주 가능한 가장 열린 각도.
    public var maxAngle: Double
    /// minAngle에서 나는 주파수.
    public var lowFrequency: Double
    /// 음역 (옥타브 수).
    public var octaves: Double

    public init(minAngle: Double = 30, maxAngle: Double = 130, lowFrequency: Double = 261.6256, octaves: Double = 2) {
        self.minAngle = minAngle
        self.maxAngle = maxAngle
        self.lowFrequency = lowFrequency
        self.octaves = octaves
    }

    public var highFrequency: Double { lowFrequency * pow(2, octaves) }

    /// 반음 하나에 해당하는 각도(°).
    public var degreesPerSemitone: Double { (maxAngle - minAngle) / (octaves * 12) }

    /// 각도가 연주 범위 안인지. 너무 닫으면 화면이 안 보이고 잠자기 위험이 있어서 하한 아래에선 소리를 끈다.
    public func isPlayable(_ angle: Double) -> Bool { angle >= minAngle }

    /// 각도 → 주파수. 범위 밖은 양 끝으로 고정한다.
    public func frequency(for angle: Double) -> Double {
        let t = min(max((angle - minAngle) / (maxAngle - minAngle), 0), 1)
        return lowFrequency * pow(2, t * octaves)
    }
}

/// 주파수와 음이름 변환 (A4 = 440Hz, 12평균율).
public enum Note {
    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// 주파수 → MIDI 번호 (실수). 69 = A4.
    public static func midi(for frequency: Double) -> Double {
        69 + 12 * log2(frequency / 440)
    }

    public static func frequency(midi: Double) -> Double {
        440 * pow(2, (midi - 69) / 12)
    }

    /// 가장 가까운 음이름과 센트 차이. 예: ("A4", +12)
    public static func nearest(to frequency: Double) -> (name: String, cents: Double) {
        let m = midi(for: frequency)
        let rounded = Int(m.rounded())
        let name = names[((rounded % 12) + 12) % 12] + String(rounded / 12 - 1)
        return (name, (m - Double(rounded)) * 100)
    }
}
