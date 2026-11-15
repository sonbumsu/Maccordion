import AVFoundation

/// AVAudioEngine에 테레민 음성과 아코디언 신스를 붙여서 실제로 소리를 낸다. 두 소리는 더해서 나간다.
///
/// 파라미터는 아무 스레드에서나 바꿔도 된다. 64비트 정렬된 Double 하나를 쓰고 읽는 것뿐이라
/// arm64/x86_64에서 찢어진 값이 나오지 않고, 오디오 콜백은 락을 잡지 않는다.
public final class SynthEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private enum Slot { static let frequency = 0, amplitude = 1, bellows = 2, count = 3 }
    private let params = UnsafeMutablePointer<Double>.allocate(capacity: Slot.count)
    private let gates = UnsafeMutablePointer<Double>.allocate(capacity: AccordionSynth.noteCount)

    /// 테레민 목표 주파수(Hz).
    public var targetFrequency: Double {
        get { params[Slot.frequency] }
        set { params[Slot.frequency] = newValue }
    }

    /// 테레민 목표 음량 (0~1).
    public var targetAmplitude: Double {
        get { params[Slot.amplitude] }
        set { params[Slot.amplitude] = min(max(newValue, 0), 1) }
    }

    /// 아코디언 바람 (0~1).
    public var bellowsPressure: Double {
        get { params[Slot.bellows] }
        set { params[Slot.bellows] = min(max(newValue, 0), 1) }
    }

    /// 아코디언 노트 크기 설정. 0이면 뗌.
    public func setGate(midi: Int, level: Double) {
        guard (0..<AccordionSynth.noteCount).contains(midi) else { return }
        gates[midi] = level
    }

    public func clearGates() {
        for i in 0..<AccordionSynth.noteCount { gates[i] = 0 }
    }

    /// 테레민 음량 상한. 사인파를 최대 음량으로 내면 귀가 아프다.
    public var thereminGain: Double = 0.4

    public init() {
        params[Slot.frequency] = 440
        params[Slot.amplitude] = 0
        params[Slot.bellows] = 0
        gates.initialize(repeating: 0, count: AccordionSynth.noteCount)
    }

    deinit {
        stop()
        params.deallocate()
        gates.deallocate()
    }

    public func start() throws {
        guard sourceNode == nil else { return }
        let output = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : 48_000
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        var voice = ThereminVoice(sampleRate: sampleRate, initialFrequency: params[Slot.frequency])
        let accordion = AccordionSynth(sampleRate: sampleRate)
        // 오디오 콜백에서 할당하지 않도록 임시 버퍼를 미리 잡는다.
        let scratchSize = 8192
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchSize)
        let params = self.params
        let gates = UnsafePointer(self.gates)
        let gain = thereminGain

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n = min(Int(frameCount), scratchSize)

            voice.render(into: out, count: n, targetFrequency: params[Slot.frequency],
                         targetAmplitude: params[Slot.amplitude] * gain)
            accordion.render(into: scratch, count: n, gates: gates, targetPressure: params[Slot.bellows])
            for i in 0..<n { out[i] += scratch[i] }

            // 모노 소스지만 출력 쪽 버퍼가 여럿이면 복사해준다.
            for b in buffers.dropFirst() {
                b.mData?.copyMemory(from: out, byteCount: Int(b.mDataByteSize))
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        sourceNode = node
    }

    public func stop() {
        engine.stop()
        if let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
    }
}
