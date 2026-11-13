import Foundation

/// 원시 각도(정수 °)를 연주용 실수 각도로 다듬는다.
/// 원시 각도 ─▶ 이상치 제거 ─▶ One Euro 필터 ─▶ 보간 각도
public struct AngleSmoother {
    /// 한 샘플에 이보다 크게 튀면 버린다(°).
    public var outlierThreshold: Double
    /// 이상치가 이만큼 연속되면 진짜 움직임으로 보고 받아들인다.
    public var outlierAcceptCount: Int
    public var filter: OneEuroFilter

    private var lastAccepted: Double?
    private var rejectedInARow = 0

    public init(outlierThreshold: Double = 20, outlierAcceptCount: Int = 3, filter: OneEuroFilter = OneEuroFilter()) {
        self.outlierThreshold = outlierThreshold
        self.outlierAcceptCount = outlierAcceptCount
        self.filter = filter
    }

    /// 다듬은 각도를 돌려준다. 이상치로 버린 샘플이면 nil.
    public mutating func process(_ raw: Double, at time: TimeInterval) -> Double? {
        if let last = lastAccepted, abs(raw - last) > outlierThreshold {
            rejectedInARow += 1
            guard rejectedInARow >= outlierAcceptCount else { return nil }
            // 같은 방향으로 계속 크게 벗어나면 센서가 맞다고 보고 필터를 새로 시작한다.
            filter.reset()
        }
        rejectedInARow = 0
        lastAccepted = raw
        return filter.filter(raw, at: time)
    }

    /// 지금 각속도(°/s).
    public var velocity: Double { filter.velocity }
}
