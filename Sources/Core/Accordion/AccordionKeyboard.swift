import Foundation

/// 맥 키보드를 아코디언 건반으로 쓴다. 자판 배열(한/영)과 상관없이 물리 키 위치(keyCode)로 정한다.
///
/// - 오른손 멜로디: 가운데 줄 = 흰 건반, 윗줄 = 검은 건반 (DAW에서 흔한 배치)
/// - 왼손 화음: 아랫줄 = 베이스 + 3화음 (스트라델라 베이스를 단순화)
public struct AccordionKeyboard {
    public struct Key {
        public let keyCode: UInt16
        public let label: String
        /// 소리낼 MIDI 노트와 각 음의 크기(0~1).
        public let notes: [(midi: Int, level: Double)]
        public let isChord: Bool
    }

    /// 멜로디 기준 옥타브 이동 (반음 단위가 아니라 옥타브 단위).
    public var octaveShift = 0

    public static let melodyKeys: [(keyCode: UInt16, label: String, offset: Int)] = [
        (0, "A", 0), (13, "W", 1), (1, "S", 2), (14, "E", 3), (2, "D", 4),
        (3, "F", 5), (17, "T", 6), (5, "G", 7), (16, "Y", 8), (4, "H", 9),
        (32, "U", 10), (38, "J", 11), (40, "K", 12), (31, "O", 13), (37, "L", 14),
        (35, "P", 15), (41, ";", 16), (39, "'", 17),
    ]

    /// (keyCode, 라벨, 화음 이름, 근음 pitch class, 단조 여부)
    public static let chordKeys: [(keyCode: UInt16, label: String, name: String, root: Int, minor: Bool)] = [
        (6, "Z", "C", 0, false), (7, "X", "F", 5, false), (8, "C", "G", 7, false),
        (9, "V", "Am", 9, true), (11, "B", "Dm", 2, true), (45, "N", "Em", 4, true),
    ]

    public static let melodyBase = 60   // C4

    public init() {}

    public func key(for keyCode: UInt16) -> Key? {
        if let m = Self.melodyKeys.first(where: { $0.keyCode == keyCode }) {
            let midi = Self.melodyBase + m.offset + octaveShift * 12
            return Key(keyCode: keyCode, label: m.label, notes: [(midi, 1.0)], isChord: false)
        }
        if let c = Self.chordKeys.first(where: { $0.keyCode == keyCode }) {
            return Key(keyCode: keyCode, label: c.label, notes: Self.chordNotes(root: c.root, minor: c.minor), isChord: true)
        }
        return nil
    }

    /// 베이스(옥타브 2) + 3화음(옥타브 3). 반주가 멜로디를 덮지 않게 작게 낸다.
    public static func chordNotes(root: Int, minor: Bool) -> [(midi: Int, level: Double)] {
        let bass = 36 + root                 // C2 ~ B2
        let chordRoot = 48 + root            // C3 ~ B3
        let third = minor ? 3 : 4
        return [(bass, 0.6), (chordRoot, 0.35), (chordRoot + third, 0.35), (chordRoot + 7, 0.35)]
    }
}

/// 지금 눌린 키들로부터 노트별 크기를 계산한다. 같은 음을 두 키가 함께 누르고 있어도
/// 한쪽을 뗄 때 소리가 끊기지 않게 키 단위로 기억한다.
public struct HeldNotes {
    private var held: [UInt16: [(midi: Int, level: Double)]] = [:]

    public init() {}

    /// 새로 눌렸으면 true.
    @discardableResult
    public mutating func press(_ key: AccordionKeyboard.Key) -> Bool {
        guard held[key.keyCode] == nil else { return false }
        held[key.keyCode] = key.notes
        return true
    }

    public mutating func release(keyCode: UInt16) {
        held[keyCode] = nil
    }

    public mutating func releaseAll() {
        held.removeAll()
    }

    public var heldKeyCodes: Set<UInt16> { Set(held.keys) }

    /// MIDI 노트 → 크기. 여러 키가 같은 음을 누르면 큰 쪽을 쓴다.
    public var levels: [Int: Double] {
        var out: [Int: Double] = [:]
        for notes in held.values {
            for n in notes { out[n.midi] = max(out[n.midi] ?? 0, n.level) }
        }
        return out
    }
}
