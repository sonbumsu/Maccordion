import AppKit

/// 메인 화면. 모드에 따라 입력을 나눠 보내고 그린다.
/// - 테레민: 트랙패드 압력/스페이스바 = 음량, 뚜껑 각도 = 음높이
/// - 아코디언: 키보드 = 건반, 뚜껑 여닫는 속도 = 바람
final class PlayView: NSView {
    let controller: ThereminController

    private var isPressing = false
    private var pressure: Double = 0
    private var stage = 0
    private var isSpaceDown = false
    private var redrawTimer: Timer?
    private var resignObserver: NSObjectProtocol?
    private var lastSignature = ""

    /// 화면에 보이는 값만 화면 표시 정밀도로 묶은 문자열.
    private func displaySignature() -> String {
        let c = controller
        let angle = c.angle.map { String(format: "%.1f", $0) } ?? "-"
        let keys = c.held.heldKeyCodes.sorted().map(String.init).joined(separator: ",")
        return [
            c.mode == .accordion ? "A" : "T", angle,
            String(format: "%.1f|%.2f|%.2f", c.frequency, c.pressure, c.volume),
            "\(c.bellowsDirection)", keys, "\(c.keyboard.octaveShift)", c.sensorError ?? "",
        ].joined(separator: "|")
    }

    private enum KeyCode {
        static let space: UInt16 = 49, tab: UInt16 = 48, up: UInt16 = 126, down: UInt16 = 125
    }

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
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        guard let window else { return }
        // 글자 그리기가 비싸므로, 화면에 보이는 값이 바뀌었을 때만 다시 그린다.
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let signature = self.displaySignature()
            if signature != self.lastSignature {
                self.lastSignature = signature
                self.needsDisplay = true
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.controller.releaseAllKeys()
            self?.isSpaceDown = false
            self?.isPressing = false
            self?.updateVolume()
        }
    }

    // MARK: - 입력

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
        if event.modifierFlags.contains(.command) { return super.keyDown(with: event) }
        switch event.keyCode {
        case KeyCode.tab:
            if !event.isARepeat {
                isSpaceDown = false
                controller.toggleMode()
                updateVolume()
            }
        case KeyCode.up where controller.mode == .accordion:
            controller.shiftOctave(+1)
        case KeyCode.down where controller.mode == .accordion:
            controller.shiftOctave(-1)
        case KeyCode.space where controller.mode == .theremin:
            if !event.isARepeat { isSpaceDown = true; updateVolume() }
        default:
            if event.isARepeat, controller.mode == .accordion { return }
            if !controller.keyDown(keyCode: event.keyCode) { super.keyDown(with: event) }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == KeyCode.space { isSpaceDown = false; updateVolume(); return }
        _ = controller.keyUp(keyCode: event.keyCode)
    }

    /// 테레민 모드: 클릭(1단계)부터 포스 클릭(2단계) 끝까지를 0.2~1.0 음량으로 펼친다.
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

        let modeName = controller.mode == .accordion ? "아코디언" : "테레민"
        drawText("\(modeName) 모드   (Tab: 모드 바꾸기)", at: NSPoint(x: 32, y: 20), size: 14, color: .secondaryLabelColor)

        switch controller.mode {
        case .theremin: drawTheremin(angle: angle)
        case .accordion: drawAccordion(angle: angle)
        }
    }

    // MARK: 테레민

    private func drawTheremin(angle: Double) {
        let playable = controller.isPlayable
        drawLid(angle: angle, color: playable ? .systemTeal : .systemOrange, folds: false)

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

        drawPitchBar()
        drawMeter(label: "음량", value: controller.volume, color: .systemPink,
                  hint: "트랙패드를 누르거나 스페이스바를 누르고 있으면 소리가 나요")
    }

    /// 2옥타브 건반 막대 위에 지금 위치를 점으로 찍는다.
    private func drawPitchBar() {
        let m = controller.mapper
        let rect = NSRect(x: 32, y: bounds.height - 120, width: bounds.width - 64, height: 44)
        let semitones = Int(m.octaves * 12)
        let lowMidi = Note.midi(for: m.lowFrequency).rounded()
        let cell = rect.width / CGFloat(semitones + 1)

        for i in 0...semitones {
            let midi = Int(lowMidi) + i
            let name = noteName(midi)
            let isBlack = name.hasSuffix("#")
            let r = NSRect(x: rect.minX + CGFloat(i) * cell + 1, y: rect.minY, width: cell - 2, height: rect.height)
            (isBlack ? NSColor(calibratedWhite: 0.2, alpha: 1) : NSColor(calibratedWhite: 0.85, alpha: 1)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            if !isBlack {
                drawText(name, at: NSPoint(x: r.midX - 5, y: r.maxY + 4), size: 12, color: .secondaryLabelColor)
            }
        }

        guard controller.isPlayable else { return }
        let pos = Note.midi(for: controller.frequency) - lowMidi
        let dotX = rect.minX + CGFloat(pos + 0.5) * cell
        let dot = NSRect(x: dotX - 8, y: rect.midY - 8, width: 16, height: 16)
        (controller.volume > 0 ? NSColor.systemPink : NSColor.systemTeal).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    // MARK: 아코디언

    private func drawAccordion(angle: Double) {
        let p = controller.pressure
        let color = NSColor.systemYellow.blended(withFraction: 1 - p, of: NSColor(calibratedWhite: 0.6, alpha: 1))!
        drawLid(angle: angle, color: color, folds: true)

        let x = bounds.width * 0.52
        let dirText: String
        switch controller.bellowsDirection {
        case .still: dirText = "뚜껑을 여닫아 바람을 넣어요"
        case .opening: dirText = "당기는 중 ▲"
        case .closing: dirText = "미는 중 ▼"
        }
        drawText(dirText, at: NSPoint(x: x, y: 60), size: 26, color: p > 0 ? .systemYellow : .secondaryLabelColor)

        let names = controller.held.levels.keys.sorted().map(noteName)
        drawText(names.isEmpty ? "–" : names.joined(separator: " "),
                 at: NSPoint(x: x, y: 110), size: 30, color: .white)
        let shift = controller.keyboard.octaveShift
        drawText("옥타브 \(shift >= 0 ? "+" : "")\(shift)  (↑↓)", at: NSPoint(x: x, y: 160),
                 size: 14, color: .secondaryLabelColor)

        drawMelodyKeys()
        drawChordKeys()
        drawMeter(label: "바람", value: p, color: .systemYellow,
                  hint: "건반을 누른 채로 뚜껑을 여닫으면 소리가 나요")
    }

    /// 피아노처럼 흰 건반(가운데 줄)과 검은 건반(윗줄)을 그린다.
    private func drawMelodyKeys() {
        let held = controller.held.heldKeyCodes
        let whites = AccordionKeyboard.melodyKeys.filter { !noteName(AccordionKeyboard.melodyBase + $0.offset).hasSuffix("#") }
        let area = NSRect(x: 32, y: bounds.height - 230, width: bounds.width - 64, height: 100)
        let w = area.width / CGFloat(whites.count)
        var whiteX: [Int: CGFloat] = [:]   // offset → 왼쪽 x

        for (i, k) in whites.enumerated() {
            let r = NSRect(x: area.minX + CGFloat(i) * w + 1, y: area.minY, width: w - 2, height: area.height)
            whiteX[k.offset] = r.minX
            (held.contains(k.keyCode) ? NSColor.systemYellow : NSColor(calibratedWhite: 0.88, alpha: 1)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            let midi = AccordionKeyboard.melodyBase + k.offset + controller.keyboard.octaveShift * 12
            drawText(k.label, at: NSPoint(x: r.midX - 5, y: r.maxY - 40), size: 15, color: .black)
            drawText(noteName(midi), at: NSPoint(x: r.midX - 9, y: r.maxY - 20), size: 11, color: .darkGray)
        }
        for k in AccordionKeyboard.melodyKeys where noteName(AccordionKeyboard.melodyBase + k.offset).hasSuffix("#") {
            guard let leftX = whiteX[k.offset - 1] else { continue }
            let r = NSRect(x: leftX + w * 0.62, y: area.minY, width: w * 0.72, height: area.height * 0.58)
            (held.contains(k.keyCode) ? NSColor.systemOrange : NSColor(calibratedWhite: 0.15, alpha: 1)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            drawText(k.label, at: NSPoint(x: r.midX - 5, y: r.maxY - 22), size: 13, color: .white)
        }
    }

    /// 왼손 화음 버튼(아랫줄).
    private func drawChordKeys() {
        let held = controller.held.heldKeyCodes
        let y = bounds.height - 110
        drawText("화음", at: NSPoint(x: 32, y: y + 14), size: 14, color: .secondaryLabelColor)
        for (i, c) in AccordionKeyboard.chordKeys.enumerated() {
            let r = NSRect(x: 80 + CGFloat(i) * 76, y: y, width: 66, height: 46)
            (held.contains(c.keyCode) ? NSColor.systemYellow : NSColor(calibratedWhite: 0.22, alpha: 1)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 23, yRadius: 23).fill()
            let textColor: NSColor = held.contains(c.keyCode) ? .black : .white
            drawText(c.name, at: NSPoint(x: r.minX + 14, y: r.minY + 6), size: 17, color: textColor)
            drawText(c.label, at: NSPoint(x: r.maxX - 22, y: r.minY + 24), size: 11, color: textColor.withAlphaComponent(0.6))
        }
    }

    // MARK: 공통

    /// 옆에서 본 맥북. 경첩을 기준으로 화면이 실제 각도만큼 열린다. folds면 바람통 주름을 그린다.
    private func drawLid(angle: Double, color: NSColor, folds: Bool) {
        let hinge = NSPoint(x: 200, y: 240)
        let length: CGFloat = 150
        let rad = angle * .pi / 180
        let tip = NSPoint(x: hinge.x - length * cos(rad), y: hinge.y - length * sin(rad))
        let baseEnd = NSPoint(x: hinge.x - length, y: hinge.y)

        if folds && angle > 2 {
            // 바닥과 화면 끝 사이를 지그재그로 잇는 주름
            let path = NSBezierPath()
            let count = 9
            for i in 0...count {
                let t = CGFloat(i) / CGFloat(count)
                let a = rad * Double(t)
                let r: CGFloat = i % 2 == 0 ? length : length * 0.82
                let pt = NSPoint(x: hinge.x - r * cos(a), y: hinge.y - r * sin(a))
                i == 0 ? path.move(to: pt) : path.line(to: pt)
            }
            path.lineWidth = 3
            path.lineJoinStyle = .round
            color.withAlphaComponent(0.7).setStroke()
            path.stroke()
        }

        let base = NSBezierPath()
        base.move(to: hinge); base.line(to: baseEnd)
        base.lineWidth = 8; base.lineCapStyle = .round
        NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
        base.stroke()

        let lid = NSBezierPath()
        lid.move(to: hinge); lid.line(to: tip)
        lid.lineWidth = 8; lid.lineCapStyle = .round
        color.setStroke()
        lid.stroke()

        drawText(String(format: "%.0f°", angle), at: NSPoint(x: hinge.x + 14, y: hinge.y - 12), size: 14,
                 color: .secondaryLabelColor)
    }

    private func drawMeter(label: String, value: Double, color: NSColor, hint: String) {
        let y = bounds.height - 40
        drawText(label, at: NSPoint(x: 32, y: y - 2), size: 14, color: .secondaryLabelColor)
        let track = NSRect(x: 80, y: y, width: 200, height: 12)
        NSColor(calibratedWhite: 0.25, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 6, yRadius: 6).fill()
        var fill = track
        fill.size.width *= value
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 6, yRadius: 6).fill()
        drawText(hint, at: NSPoint(x: 300, y: y - 2), size: 13, color: .secondaryLabelColor)
    }

    private func noteName(_ midi: Int) -> String {
        Note.nearest(to: Note.frequency(midi: Double(midi))).name
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: size > 30 ? .bold : .regular),
            .foregroundColor: color,
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}
