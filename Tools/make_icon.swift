import AppKit

// 앱 아이콘 원본(1024px PNG)을 그린다. build.sh icon 이 이것으로 Resources/AppIcon.icns를 만든다.
// 사용법: make_icon <로고.png> <출력.png>

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high

// macOS 아이콘 격자: 1024 안에 824 크기의 둥근 사각형
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.current!.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.current!.restoreGraphicsState()

// 로고 색(연보라)에 맞춘 어두운 보라 그라디언트
NSGradient(starting: NSColor(red: 0.30, green: 0.24, blue: 0.46, alpha: 1),
           ending: NSColor(red: 0.12, green: 0.10, blue: 0.20, alpha: 1))!.draw(in: tilePath, angle: -90)

// 로고를 타일 안에 비율을 유지하며 얹는다 (타일 안쪽 여백 40).
let logo = NSImage(contentsOfFile: CommandLine.arguments[1])!
let inner = tile.insetBy(dx: 40, dy: 40)
let scale = min(inner.width / logo.size.width, inner.height / logo.size.height)
let drawSize = NSSize(width: logo.size.width * scale, height: logo.size.height * scale)
let drawRect = NSRect(x: inner.midX - drawSize.width / 2, y: inner.midY - drawSize.height / 2,
                      width: drawSize.width, height: drawSize.height)
NSGraphicsContext.current!.saveGraphicsState()
tilePath.addClip()
logo.draw(in: drawRect)
NSGraphicsContext.current!.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
