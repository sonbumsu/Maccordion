import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 검은 배경 로고를 투명 배경 PNG로 바꾼다. 투명한 여백은 잘라낸다.
// 사용법: remove_background <입력.png> <출력.png>
//
// 바깥 테두리에서부터 거의 검은 픽셀(배경)만 4방향으로 채워 나가며 지운다.
// 스티커는 흰 테두리로 둘러싸여 있으므로 안쪽의 검은 부분(베레모, 아코디언)은 지워지지 않는다.
// 배경과 흰 테두리 사이의 반쯤 섞인 픽셀은 밝기만큼 알파를 주고 색을 되돌려서 가장자리를 매끄럽게 한다.

let args = CommandLine.arguments
guard args.count == 3 else { print("사용법: remove_background <입력.png> <출력.png>"); exit(1) }

let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let w = image.width, h = image.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpaceCreateDeviceRGB()
let info = CGImageAlphaInfo.premultipliedLast.rawValue
CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info)!
    .draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

func brightness(_ i: Int) -> Int { max(Int(px[i * 4]), Int(px[i * 4 + 1]), Int(px[i * 4 + 2])) }

let backgroundMax = 12      // 이 밝기 이하면 배경
let edgeMax = 200           // 배경 옆에서 이 밝기 미만이면 반투명 가장자리

// 1) 테두리에서 배경 채우기
var isBackground = [Bool](repeating: false, count: w * h)
var stack: [Int] = []
for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
while let i = stack.popLast() {
    guard !isBackground[i], brightness(i) <= backgroundMax else { continue }
    isBackground[i] = true
    let x = i % w, y = i / w
    if x > 0 { stack.append(i - 1) }
    if x < w - 1 { stack.append(i + 1) }
    if y > 0 { stack.append(i - w) }
    if y < h - 1 { stack.append(i + w) }
}

// 2) 배경 지우기 + 가장자리 2픽셀 반투명 처리
var alpha = [UInt8](repeating: 255, count: w * h)
for i in 0..<(w * h) where isBackground[i] { alpha[i] = 0 }
var ring = isBackground
for _ in 0..<2 {
    var next = ring
    for y in 1..<(h - 1) {
        for x in 1..<(w - 1) {
            let i = y * w + x
            guard !ring[i], ring[i - 1] || ring[i + 1] || ring[i - w] || ring[i + w] else { continue }
            let b = brightness(i)
            if b < edgeMax {
                // 검은 배경 위에 섞인 색: c = a·원래색  →  a = 밝기/흰테두리밝기
                alpha[i] = UInt8(min(255, b * 255 / edgeMax))
                next[i] = true
            }
        }
    }
    ring = next
}

// 3) 출력 버퍼 (premultiplied). 배경 위 섞인 색은 이미 a·원래색이므로 RGB는 그대로 둔다.
var out = [UInt8](repeating: 0, count: w * h * 4)
var minX = w, minY = h, maxX = 0, maxY = 0
for i in 0..<(w * h) where alpha[i] > 0 {
    let a = Int(alpha[i])
    out[i * 4] = UInt8(min(Int(px[i * 4]), a))
    out[i * 4 + 1] = UInt8(min(Int(px[i * 4 + 1]), a))
    out[i * 4 + 2] = UInt8(min(Int(px[i * 4 + 2]), a))
    out[i * 4 + 3] = UInt8(a)
    let x = i % w, y = i / w
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
}

let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info)!
let full = ctx.makeImage()!
// CGImage 좌표는 위에서부터이므로 그대로 자른다. 여백 8픽셀을 남긴다.
let pad = 8
let crop = CGRect(x: max(minX - pad, 0), y: max(minY - pad, 0),
                  width: min(maxX + pad, w - 1) - max(minX - pad, 0) + 1,
                  height: min(maxY + pad, h - 1) - max(minY - pad, 0) + 1)
let cropped = full.cropping(to: crop)!

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cropped, nil)
CGImageDestinationFinalize(dest)
let removed = isBackground.filter { $0 }.count
print("배경 \(removed)픽셀 제거 (\(removed * 100 / (w * h))%), 출력 \(cropped.width)×\(cropped.height)")
