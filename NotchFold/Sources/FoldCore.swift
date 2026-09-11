import AppKit
import CoreVideo

/// 5 种折叠效果定义（对应 Metal Shader 中的 effect 索引）
public enum FoldEffect: String, CaseIterable, Sendable, Identifiable {
    case duo, flex, roll, shutter, iris

    public static let fallback = FoldEffect.duo

    public var id: String { rawValue }

    public var shaderIndex: UInt32 {
        switch self {
        case .duo: return 0
        case .roll: return 1
        case .shutter: return 2
        case .flex: return 3
        case .iris: return 4
        }
    }

    public static func resolve(persisted: String?) -> FoldEffect {
        guard let persisted, let effect = FoldEffect(rawValue: persisted) else { return fallback }
        return effect
    }

    public var title: String {
        switch self {
        case .duo: return "Duo (流体对折)"
        case .flex: return "Flex (曲面流体)"
        case .roll: return "Roll (卷轴)"
        case .shutter: return "Shutter (百叶窗)"
        case .iris: return "Iris (机械光圈)"
        }
    }

    public var summary: String {
        switch self {
        case .duo: return "屏幕以转轴为底展开，顶部纵深景深模糊渐变"
        case .flex: return "屏幕呈流体曲面穹顶向前弯折，带法线高光反光带"
        case .roll: return "桌面卷曲成圆柱卷轴顺滑卷向转轴"
        case .shutter: return "四层刚性百叶窗面板错层向底座叠落"
        case .iris: return "八片机械光圈叶片在上方向转轴平滑收拢"
        }
    }

    public var needsPrefilteredSource: Bool { self != .duo }
}

/// 32 字节，与 Metal Fragment Shader 中的 Uniforms 严格按字节对齐
public struct FoldUniforms: Equatable {
    public var progress: Float = 0
    public var perspective: Float = 0.7
    public var blur: Float = 0.65
    public var shadow: Float = 0.65
    public var size = SIMD2<Float>(1, 1)
    public var fadeOnly: Float = 0
    public var effect: UInt32 = 0 // 默认 Duo

    public init() {}

    public var selectedEffect: FoldEffect {
        switch effect {
        case 0: return .duo
        case 1: return .roll
        case 2: return .shutter
        case 3: return .flex
        case 4: return .iris
        default: return .duo
        }
    }
}

/// 物理传感器平滑插值与度数转进度算子
public enum FoldMath {
    public static func progress(angle: Double, clearAngle: Double = 105.0) -> Double {
        guard angle.isFinite, clearAngle.isFinite else { return 0 }
        let clear = min(140.0, max(60.0, clearAngle))
        let t = min(1.0, max(0.0, (clear - angle) / (clear - 5.0)))
        return t * t * (3.0 - 2.0 * t) // smoothstep
    }

    public static func smooth(current: Double, target: Double, dt: Double) -> Double {
        guard current.isFinite, target.isFinite, dt.isFinite else { return 0 }
        let t = min(1.0, max(0.0, target))
        let next = current + (t - current) * (1.0 - exp(-max(0.0, dt) / 0.045))
        return abs(next - t) < 0.0001 ? t : next
    }

    public static func decodeReport(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3, bytes[0] == 1 else { return nil }
        let angle = Int(bytes[1]) | (Int(bytes[2]) << 8)
        guard (0...180).contains(angle) else { return nil }
        return Double(angle)
    }
}

/// 静止检测器：当合盖停止在某一度数超过 2 秒时，自动让屏幕平滑变清晰，方便半合盖时阅读
public struct LidStillness {
    public private(set) var isStill = false
    private var anchor: Double?
    private var stationarySince: TimeInterval?
    private var lastReadingAt: TimeInterval?

    public init() {}

    public mutating func reset() { self = LidStillness() }

    @discardableResult
    public mutating func observe(angle: Double?, at now: TimeInterval, delay: TimeInterval = 2.0) -> Bool {
        guard let angle, angle.isFinite, (0...180).contains(angle), now.isFinite else {
            reset()
            return false
        }
        if let previous = lastReadingAt, now < previous || now - previous > 1.0 {
            reset()
        }
        lastReadingAt = now
        let interval = delay.isFinite ? min(5.0, max(1.0, delay)) : 2.0
        if anchor == nil || abs(angle - anchor!) >= 2.0 {
            anchor = angle
            stationarySince = now
            isStill = false
        } else if let since = stationarySince, now - since >= interval {
            isStill = true
        }
        return isStill
    }
}

/// 线程安全的实时屏幕捕获帧存储
public final class FrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var receivedAt: TimeInterval = 0
    private var revision: UInt64 = 0

    public init() {}

    public func put(_ value: CVPixelBuffer) {
        lock.lock()
        buffer = value
        receivedAt = ProcessInfo.processInfo.systemUptime
        revision &+= 1
        lock.unlock()
    }

    public func get() -> (CVPixelBuffer?, TimeInterval, UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (buffer, receivedAt, revision)
    }

    public func clear() {
        lock.lock()
        buffer = nil
        receivedAt = 0
        revision &+= 1
        lock.unlock()
    }
}
