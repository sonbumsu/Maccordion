import Foundation
import IOKit.hid

/// 맥북 뚜껑 각도 센서(비공개 HID 장치)를 폴링한다.
///
/// - 장치: VendorID 0x05AC, ProductID 0x8104, UsagePage 0x20(Sensor), Usage 0x8A(Orientation)
/// - Feature Report ID 1 → 3바이트 `[0x01, lo, hi]`, 각도(°) = lo | hi << 8
///
/// Apple이 공개한 API가 아니므로, 센서 접근은 이 파일에만 둔다.
public final class LidAngleSensor: AngleSource {
    public var onSample: ((Double, TimeInterval) -> Void)?

    private let pollHz: Double
    private let queue = DispatchQueue(label: "LidAngleSensor.poll", qos: .userInteractive)
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?

    public init(pollHz: Double = 120) {
        self.pollHz = pollHz
    }

    deinit { stop() }

    /// 센서가 있는지만 빠르게 확인한다.
    public static func isAvailable() -> Bool {
        let sensor = LidAngleSensor()
        defer { sensor.stop() }
        return (try? sensor.open()) != nil && sensor.readAngle() != nil
    }

    public func start() throws {
        guard timer == nil else { return }
        try open()

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0 / pollHz, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            guard let self, let angle = self.readAngle() else { return }
            self.onSample?(angle, ProcessInfo.processInfo.systemUptime)
        }
        timer = t
        t.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        manager = nil
    }

    /// 한 번 읽어서 각도(°)를 돌려준다. 실패하면 nil.
    public func readAngle() -> Double? {
        guard let device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        return Double(Int(report[1]) | Int(report[2]) << 8)
    }

    @discardableResult
    private func open() throws -> IOHIDDevice {
        if let device { return device }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDProductIDKey: 0x8104,
            kIOHIDPrimaryUsagePageKey: 0x20,
            kIOHIDPrimaryUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            throw AngleSourceError.sensorNotFound
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw AngleSourceError.openFailed(result) }
        self.device = device
        return device
    }
}
