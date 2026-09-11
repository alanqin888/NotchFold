import Cocoa
import IOKit
import IOKit.hid

public final class LidMonitor {
    public static let shared = LidMonitor()
    
    public var onAngleChanged: ((Double) -> Void)?
    public var onLidStateChanged: ((Bool) -> Void)?
    
    public private(set) var currentAngle: Double = 100.0
    public private(set) var isLidClosed: Bool = false
    
    private var hidManager: IOHIDManager?
    private var sleepObserver1: Any?
    private var sleepObserver2: Any?
    private var wakeObserver: Any?
    
    private init() {
        setupHIDSensor()
        setupSleepNotifications()
    }
    
    private func setupHIDSensor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager
        
        // 匹配 Apple Silicon 的 Lid Angle Sensor (las)
        // UsagePage 0x20 (32: Sensors), Usage 0x8A (138: Hinge Angle)
        let matchDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 32,
            kIOHIDDeviceUsageKey: 138
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, type, reportID, report, reportLength in
            guard let context = context else { return }
            let monitor = Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue()
            
            if reportID == 1 && reportLength >= 3 {
                let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
                let angleRaw = Int(bytes[1]) | (Int(bytes[2]) << 8)
                let angle = Double(angleRaw)
                
                DispatchQueue.main.async {
                    monitor.handleAngleUpdate(angle)
                }
            }
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let res = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if res == kIOReturnSuccess {
            print("✅ LidMonitor: 成功接管 Apple Silicon 物理开合角度传感器 (las)")
        } else {
            print("⚠️ LidMonitor: 无法打开传感器，错误码: \(res)")
        }
    }
    
    private func handleAngleUpdate(_ angle: Double) {
        // 过滤异常抖动
        guard angle >= 0.0 && angle <= 180.0 else { return }
        self.currentAngle = angle
        self.isLidClosed = (angle <= 5.0)
        onAngleChanged?(angle)
    }
    
    private func setupSleepNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        
        sleepObserver1 = center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isLidClosed = true
            self?.onLidStateChanged?(true)
            self?.onAngleChanged?(0.0)
        }
        
        sleepObserver2 = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isLidClosed = true
            self?.onLidStateChanged?(true)
            self?.onAngleChanged?(0.0)
        }
        
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isLidClosed = false
            self?.onLidStateChanged?(false)
            self?.onAngleChanged?(100.0)
        }
    }
    
    deinit {
        if let m = hidManager {
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let o1 = sleepObserver1 { NSWorkspace.shared.notificationCenter.removeObserver(o1) }
        if let o2 = sleepObserver2 { NSWorkspace.shared.notificationCenter.removeObserver(o2) }
        if let o3 = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o3) }
    }
}
