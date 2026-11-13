import Foundation

/// 뚜껑 각도를 내보내는 입력원. 실제 센서, 대체 입력, 녹화 재생이 모두 이 인터페이스를 따른다.
public protocol AngleSource: AnyObject {
    /// 각도 샘플이 들어올 때마다 호출된다. (각도°, 타임스탬프 초). 호출 스레드는 구현체가 정한다.
    var onSample: ((Double, TimeInterval) -> Void)? { get set }
    func start() throws
    func stop()
}

public enum AngleSourceError: Error, CustomStringConvertible {
    case sensorNotFound
    case openFailed(Int32)

    public var description: String {
        switch self {
        case .sensorNotFound: return "이 맥에서는 뚜껑 각도 센서를 찾을 수 없어요."
        case .openFailed(let code): return "센서를 열지 못했어요 (IOReturn \(code))."
        }
    }
}
