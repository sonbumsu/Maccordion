import Foundation

enum PlayMode {
    /// 각도 = 음높이, 트랙패드 = 음량
    case theremin
    /// 여닫는 속도 = 바람, 키보드 = 건반
    case accordion
}

/// 센서와 입력을 받아 지금 모드에 맞게 SynthEngine에 전달한다.
final class MaccordionController {
    let synth = SynthEngine()
    var mapper = PitchMapper()
    var keyboard = AccordionKeyboard()

    private let sensor = LidAngleSensor(pollHz: 120)
    private var smoother = AngleSmoother()
    private var bellows = Bellows()
    /// 센서 큐에서 읽는 현재 모드. 메인 스레드의 `mode`와 같은 값을 따로 둔다.
    private var sensorModeIsAccordion = false

    // 아래 값들은 메인 스레드에서 읽고 쓴다.
    private(set) var mode: PlayMode = .accordion
    private(set) var angle: Double?
    private(set) var frequency: Double = 0
    private(set) var pressure: Double = 0
    private(set) var bellowsDirection: Bellows.Direction = .still
    private(set) var sensorError: String?
    private(set) var held = HeldNotes()
    /// 테레민 모드에서 트랙패드/스페이스바로 정한 음량 (0~1).
    var volume: Double = 0 { didSet { updateThereminAmplitude() } }

    func start() {
        sensorModeIsAccordion = mode == .accordion
        sensor.onSample = { [weak self] raw, time in
            guard let self else { return }
            // 바람통은 원시 각도로 따로 계산해서 반응을 빠르게 한다.
            let p = self.bellows.update(angle: raw, at: time)
            let dir = self.bellows.direction
            if self.sensorModeIsAccordion { self.synth.bellowsPressure = p }

            guard let smooth = self.smoother.process(raw, at: time) else { return }
            let freq = self.mapper.frequency(for: smooth)
            if !self.sensorModeIsAccordion { self.synth.targetFrequency = freq }
            DispatchQueue.main.async {
                self.angle = smooth
                self.frequency = freq
                self.pressure = p
                self.bellowsDirection = dir
                self.updateThereminAmplitude()
            }
        }
        do {
            try sensor.start()
        } catch {
            sensorError = "\(error)"
        }
        do {
            try synth.start()
        } catch {
            sensorError = "오디오를 시작하지 못했어요: \(error)"
        }
    }

    func stop() {
        sensor.stop()
        synth.stop()
    }

    func toggleMode() {
        mode = mode == .theremin ? .accordion : .theremin
        let accordion = mode == .accordion
        // 센서 큐가 읽는 값. Bool 하나라 찢어질 일은 없고, 한두 샘플 늦게 반영돼도 괜찮다.
        sensorModeIsAccordion = accordion
        held.releaseAll()
        synth.clearGates()
        synth.bellowsPressure = 0
        volume = 0
        updateThereminAmplitude()
    }

    var isPlayable: Bool { angle.map(mapper.isPlayable) ?? false }

    // MARK: - 아코디언 건반

    /// 아코디언 건반이면 true (화면이 키 입력을 소비했는지).
    func keyDown(keyCode: UInt16) -> Bool {
        guard mode == .accordion, let key = keyboard.key(for: keyCode) else { return false }
        if held.press(key) { applyGates() }
        return true
    }

    func keyUp(keyCode: UInt16) -> Bool {
        guard mode == .accordion, held.heldKeyCodes.contains(keyCode) else { return false }
        held.release(keyCode: keyCode)
        applyGates()
        return true
    }

    /// 창이 포커스를 잃으면 keyUp이 안 올 수 있으므로 전부 뗀다.
    func releaseAllKeys() {
        held.releaseAll()
        applyGates()
    }

    func shiftOctave(_ delta: Int) {
        let next = min(max(keyboard.octaveShift + delta, -2), 2)
        guard next != keyboard.octaveShift else { return }
        // 누르고 있던 멜로디 음이 옛 옥타브에 남지 않게 모두 뗀다.
        held.releaseAll()
        keyboard.octaveShift = next
        applyGates()
    }

    private func applyGates() {
        let levels = held.levels
        for midi in 0..<AccordionSynth.noteCount {
            synth.setGate(midi: midi, level: levels[midi] ?? 0)
        }
    }

    private func updateThereminAmplitude() {
        synth.targetAmplitude = (mode == .theremin && isPlayable) ? volume : 0
    }
}
