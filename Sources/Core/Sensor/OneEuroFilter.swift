import Foundation

/// One Euro 필터 (Casiez et al., 2012).
/// 천천히 움직일 땐 강하게 부드럽게, 빨리 움직일 땐 지연을 줄인다.
public struct OneEuroFilter {
    /// 정지 상태의 차단 주파수(Hz). 낮을수록 떨림이 줄지만 반응이 느려진다.
    public var minCutoff: Double
    /// 속도에 따라 차단 주파수를 얼마나 올릴지. 클수록 빠른 움직임에 덜 늦는다.
    public var beta: Double
    /// 속도 추정용 차단 주파수(Hz).
    public var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTime: TimeInterval?

    public init(minCutoff: Double = 1.0, beta: Double = 0.05, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func reset() {
        lastValue = nil
        lastDerivative = 0
        lastTime = nil
    }

    /// 지금 추정 속도(단위/초). 각도라면 °/s.
    public var velocity: Double { lastDerivative }

    public mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard let prevValue = lastValue, let prevTime = lastTime else {
            lastValue = value
            lastTime = time
            return value
        }
        let dt = time - prevTime
        guard dt > 0 else { return prevValue }

        let rawDerivative = (value - prevValue) / dt
        let derivative = Self.lowPass(rawDerivative, prev: lastDerivative, alpha: Self.alpha(cutoff: derivativeCutoff, dt: dt))
        let cutoff = minCutoff + beta * abs(derivative)
        let filtered = Self.lowPass(value, prev: prevValue, alpha: Self.alpha(cutoff: cutoff, dt: dt))

        lastValue = filtered
        lastDerivative = derivative
        lastTime = time
        return filtered
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private static func lowPass(_ x: Double, prev: Double, alpha: Double) -> Double {
        alpha * x + (1 - alpha) * prev
    }
}
