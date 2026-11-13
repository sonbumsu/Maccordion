import Foundation

// M1 확인용 도구: 뚜껑 각도를 원시값/필터값/각속도로 콘솔에 찍는다.
//   ./build.sh angle          실시간 막대 표시
//   ./build.sh angle --csv    CSV 출력 (녹화용: > samples.csv)

let csv = CommandLine.arguments.contains("--csv")
let sensor = LidAngleSensor(pollHz: 120)
var smoother = AngleSmoother()
var lastPrint: TimeInterval = 0
var startTime: TimeInterval?

sensor.onSample = { raw, t in
    let start = startTime ?? t
    startTime = start
    guard let smooth = smoother.process(raw, at: t) else { return }

    if csv {
        print(String(format: "%.4f,%.0f,%.2f,%.1f", t - start, raw, smooth, smoother.velocity))
        return
    }
    // 화면 표시는 30Hz면 충분하다.
    guard t - lastPrint >= 1.0 / 30 else { return }
    lastPrint = t
    let barWidth = 50
    let filled = max(0, min(barWidth, Int(smooth / 180 * Double(barWidth))))
    let bar = String(repeating: "█", count: filled) + String(repeating: "·", count: barWidth - filled)
    let line = String(format: "원시 %3.0f°  필터 %6.2f°  속도 %+7.1f°/s  ", raw, smooth, smoother.velocity)
    FileHandle.standardOutput.write(("\r" + line + bar).data(using: .utf8)!)
}

do {
    try sensor.start()
} catch {
    FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
    exit(1)
}

if csv { print("time,raw,smooth,velocity") } else { print("뚜껑을 움직여보세요. 끝내려면 Ctrl+C") }
signal(SIGINT) { _ in print(""); exit(0) }
dispatchMain()
