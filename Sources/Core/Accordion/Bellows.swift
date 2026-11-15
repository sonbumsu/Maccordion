import Foundation

/// 뚜껑을 아코디언 바람통처럼 다룬다. 각도 자체가 아니라 **여닫는 속도**가 바람(압력)이 된다.
public struct Bellows {
    public enum Direction { case still, opening, closing }

    /// 이 속도(°/s) 아래는 센서 떨림으로 보고 무시한다.
    public var deadZone: Double = 4
    /// 이 속도(°/s)에서 압력이 최대(1)가 된다.
    public var fullSpeed: Double = 80
    /// 압력 곡선. 1보다 작으면 살살 움직여도 소리가 잘 난다.
    public var curve: Double = 0.7

    /// 바람통 전용 필터. 연주용 각도 필터보다 반응을 빠르게 잡아서 멈추면 바람도 빨리 멈춘다.
    private var filter = OneEuroFilter(minCutoff: 2.5, beta: 0.3, derivativeCutoff: 4)

    public private(set) var pressure: Double = 0
    public private(set) var velocity: Double = 0

    public init() {}

    public var direction: Direction {
        guard pressure > 0 else { return .still }
        return velocity > 0 ? .opening : .closing
    }

    /// 원시 각도 샘플을 넣으면 0~1 압력을 돌려준다.
    @discardableResult
    public mutating func update(angle: Double, at time: TimeInterval) -> Double {
        _ = filter.filter(angle, at: time)
        velocity = filter.velocity
        let speed = abs(velocity)
        let t = min(max((speed - deadZone) / (fullSpeed - deadZone), 0), 1)
        pressure = pow(t, curve)
        return pressure
    }

    public mutating func reset() {
        filter.reset()
        pressure = 0
        velocity = 0
    }
}
