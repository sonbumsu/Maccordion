import Foundation

/// 센서 → 피치, 트랙패드/키보드 → 음량을 묶어서 SynthEngine에 전달한다.
final class ThereminController {
    let synth = SynthEngine()
    var mapper = PitchMapper()

    private let sensor = LidAngleSensor(pollHz: 120)
    private var smoother = AngleSmoother()

    // 아래 값들은 메인 스레드에서 읽고 쓴다.
    private(set) var angle: Double?
    private(set) var frequency: Double = 0
    private(set) var sensorError: String?
    /// 트랙패드/스페이스바로 정한 음량 (0~1). 0이면 소리 없음.
    var volume: Double = 0 { didSet { updateAmplitude() } }

    func start() {
        sensor.onSample = { [weak self] raw, time in
            guard let self, let smooth = self.smoother.process(raw, at: time) else { return }
            // 피치는 지연을 줄이려고 센서 큐에서 바로 넘긴다.
            let freq = self.mapper.frequency(for: smooth)
            self.synth.targetFrequency = freq
            DispatchQueue.main.async {
                self.angle = smooth
                self.frequency = freq
                self.updateAmplitude()
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

    var isPlayable: Bool { angle.map(mapper.isPlayable) ?? false }

    private func updateAmplitude() {
        synth.targetAmplitude = isPlayable ? volume : 0
    }
}
