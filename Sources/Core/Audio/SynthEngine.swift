import AVFoundation

/// AVAudioEngine에 ThereminVoice를 붙여서 실제로 소리를 낸다.
///
/// 목표 주파수/음량은 아무 스레드에서나 바꿔도 된다. 64비트 정렬된 Double 하나를 쓰고 읽는 것뿐이라
/// arm64/x86_64에서 찢어진 값이 나오지 않고, 오디오 콜백은 락을 잡지 않는다.
public final class SynthEngine {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let params = UnsafeMutablePointer<Double>.allocate(capacity: 2)

    /// 목표 주파수(Hz).
    public var targetFrequency: Double {
        get { params[0] }
        set { params[0] = newValue }
    }

    /// 목표 음량 (0~1).
    public var targetAmplitude: Double {
        get { params[1] }
        set { params[1] = min(max(newValue, 0), 1) }
    }

    /// 전체 음량 상한. 사인파를 최대 음량으로 내면 귀가 아프다.
    public var masterGain: Double = 0.4

    public init() {
        params[0] = 440
        params[1] = 0
    }

    deinit {
        stop()
        params.deallocate()
    }

    public func start() throws {
        guard sourceNode == nil else { return }
        let output = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = output.sampleRate > 0 ? output.sampleRate : 48_000
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        var voice = ThereminVoice(sampleRate: sampleRate, initialFrequency: params[0])
        let params = self.params
        let gain = masterGain
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            voice.render(into: out, count: Int(frameCount), targetFrequency: params[0], targetAmplitude: params[1] * gain)
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
