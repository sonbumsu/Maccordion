import AppKit

/// 메인 화면. 트랙패드 압력/스페이스바를 받아 음량으로 쓰고, 뚜껑 각도와 음을 그린다.
final class PlayView: NSView {
    let controller: ThereminController

    private var isPressing = false
    private var pressure: Double = 0
    private var stage = 0
    private var isSpaceDown = false
    private var redrawTimer: Timer?

    init(controller: ThereminController) {
        self.controller = controller
        super.init(frame: .zero)
        // Force Touch를 끝까지 눌러도 시스템 '찾아보기' 같은 동작 대신 압력값만 받는다.
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        redrawTimer?.invalidate()
        guard window != nil else { return }
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    // MARK: - 입력 → 음량

    override func mouseDown(with event: NSEvent) {
        isPressing = true
        pressure = 0
        stage = 1
        updateVolume()
    }

    override func mouseUp(with event: NSEvent) {
        isPressing = false
        updateVolume()
    }

    override func pressureChange(with event: NSEvent) {
        pressure = Double(event.pressure)
        stage = event.stage
        updateVolume()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // space
            if !event.isARepeat { isSpaceDown = true; updateVolume() }
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { isSpaceDown = false; updateVolume() }
    }

    /// 클릭(1단계)부터 포스 클릭(2단계) 끝까지를 0.2~1.0 음량으로 펼친다.
    private func updateVolume() {
        var v = 0.0
        if isPressing {
            let level = stage >= 2 ? 1 + pressure : pressure   // 0 ~ 2
            v = 0.2 + 0.8 * min(level / 1.5, 1)
        }
        if isSpaceDown { v = max(v, 0.7) }
        controller.volume = v
    }

    // MARK: - 그리기

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        bounds.fill()

        if let error = controller.sensorError {
            drawText(error, at: NSPoint(x: 32, y: 32), size: 20, color: .systemOrange)
            return
        }
        guard let angle = controller.angle else {
            drawText("센서 기다리는 중…", at: NSPoint(x: 32, y: 32), size: 20, color: .secondaryLabelColor)
            return
        }

        drawLid(angle: angle)

        let playable = controller.isPlayable
        let x = bounds.width * 0.52
        drawText(String(format: "%.1f°", angle), at: NSPoint(x: x, y: 60), size: 44, color: .white)
        if playable {
            let note = Note.nearest(to: controller.frequency)
            drawText(note.name, at: NSPoint(x: x, y: 130), size: 64, color: .systemTeal)
            drawText(String(format: "%.1f Hz   %+.0f센트", controller.frequency, note.cents),
                     at: NSPoint(x: x, y: 210), size: 18, color: .secondaryLabelColor)
        } else {
            drawText("뚜껑을 \(Int(controller.mapper.minAngle))° 넘게 열어주세요",
                     at: NSPoint(x: x, y: 140), size: 20, color: .systemOrange)
        }

        drawKeyboard(angle: angle)
        drawVolume()
    }

    /// 옆에서 본 맥북. 경첩을 기준으로 화면이 실제 각도만큼 열린다.
    private func drawLid(angle: Double) {
        let hinge = NSPoint(x: bounds.width * 0.12 + 140, y: 230)
        let length: CGFloat = 140
        let base = NSBezierPath()
        base.move(to: hinge)
        base.line(to: NSPoint(x: hinge.x - length, y: hinge.y))
        base.lineWidth = 8
        base.lineCapStyle = .round
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        base.stroke()

        // 0° = 닫힘(바닥과 겹침), 90° = 수직. 화면 좌표는 y가 아래로 커진다.
        let rad = angle * .pi / 180
        let tip = NSPoint(x: hinge.x - length * cos(rad), y: hinge.y - length * sin(rad))
        let lid = NSBezierPath()
        lid.move(to: hinge)
        lid.line(to: tip)
        lid.lineWidth = 8
        lid.lineCapStyle = .round
        (controller.isPlayable ? NSColor.systemTeal : NSColor.systemOrange).setStroke()
        lid.stroke()
    }

    /// 2옥타브 건반 막대 위에 지금 위치를 점으로 찍는다.
    private func drawKeyboard(angle: Double) {
        let m = controller.mapper
        let rect = NSRect(x: 32, y: bounds.height - 120, width: bounds.width - 64, height: 44)
        let semitones = Int(m.octaves * 12)
        let lowMidi = Note.midi(for: m.lowFrequency).rounded()
        let cell = rect.width / CGFloat(semitones + 1)
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

        for i in 0...semitones {
            let midi = Int(lowMidi) + i
            let isBlack = names[midi % 12].hasSuffix("#")
            let r = NSRect(x: rect.minX + CGFloat(i) * cell + 1, y: rect.minY, width: cell - 2, height: rect.height)
            (isBlack ? NSColor(calibratedWhite: 0.2, alpha: 1) : NSColor(calibratedWhite: 0.85, alpha: 1)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            if !isBlack {
                drawText(names[midi % 12], at: NSPoint(x: r.midX - 5, y: r.maxY + 4), size: 12, color: .secondaryLabelColor)
            }
        }

        guard controller.isPlayable else { return }
        let pos = Note.midi(for: controller.frequency) - lowMidi   // 0 ~ semitones
        let dotX = rect.minX + CGFloat(pos + 0.5) * cell
        let dot = NSRect(x: dotX - 8, y: rect.midY - 8, width: 16, height: 16)
        (controller.volume > 0 ? NSColor.systemPink : NSColor.systemTeal).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    private func drawVolume() {
        let y = bounds.height - 40
        drawText("음량", at: NSPoint(x: 32, y: y - 2), size: 14, color: .secondaryLabelColor)
        let track = NSRect(x: 80, y: y, width: 200, height: 12)
        NSColor(calibratedWhite: 0.25, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 6, yRadius: 6).fill()
        var fill = track
        fill.size.width *= controller.volume
        NSColor.systemPink.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 6, yRadius: 6).fill()
        drawText("트랙패드를 누르거나 스페이스바를 누르고 있으면 소리가 나요",
                 at: NSPoint(x: 300, y: y - 2), size: 13, color: .secondaryLabelColor)
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: size > 30 ? .bold : .regular),
            .foregroundColor: color,
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}
