import Cocoa
import MetalKit

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

public final class FoldWindowController: NSWindowController {
    public static let shared = FoldWindowController()
    
    private var overlayPanel: OverlayPanel?
    private var metalView: MTKView?
    private var renderer: FoldRenderer?
    private let capture = DesktopCapture()
    private var stillness = LidStillness()
    
    public private(set) var isCurrentlyVisible = false
    public private(set) var isDemoRunning = false
    private var demoTimer: Timer?
    private var currentTargetProgress: Double = 0.0
    private var lastLidAngle: Double = 110.0
    
    public init() {
        super.init(window: nil)
        setupMetalPipeline()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupMetalPipeline() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        
        do {
            let r = try FoldRenderer(device: device)
            r.frames = capture.frames
            r.parameters = { [weak self] in
                var u = FoldUniforms()
                u.progress = Float(self?.currentTargetProgress ?? 0.0)
                u.perspective = Float(AppConfig.shared.perspective)
                u.blur = Float(AppConfig.shared.blur)
                u.shadow = Float(AppConfig.shared.shadow)
                u.effect = AppConfig.shared.selectedEffect.shaderIndex
                return u
            }
            r.onPresented = { [weak self] in
                guard let self = self, self.isCurrentlyVisible else { return }
                if self.overlayPanel?.alphaValue == 0 {
                    self.overlayPanel?.alphaValue = 1.0
                }
            }
            self.renderer = r
        } catch {
            print("⚠️ FoldRenderer 初始化失败: \(error)")
        }
        
        createOverlayWindow()
    }
    
    private func createOverlayWindow() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        
        // 关键安全原则：绝对忽略所有鼠标事件！即使覆盖全屏，鼠标点击也会100%穿透，严禁阻塞系统操作！
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.setFrame(screen.frame, display: false)
        
        if let renderer = self.renderer {
            let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: renderer.device)
            renderer.configure(view)
            view.isPaused = true
            panel.contentView = view
            self.metalView = view
        }
        
        self.overlayPanel = panel
        self.window = panel
    }
    
    /// 响应真实物理合盖传感器
    public func updateLidAngle(_ angle: Double) {
        lastLidAngle = angle
        guard !isDemoRunning else { return }
        
        let clearAngle = AppConfig.shared.clearAngle // 80°
        let now = ProcessInfo.processInfo.systemUptime
        let settled = stillness.observe(angle: angle, at: now, delay: 2.0)
        
        // 只有合盖角度真实低于 80° 时才进入折叠状态
        if angle < clearAngle {
            if AppConfig.shared.clearWhenStill && settled {
                currentTargetProgress = 0.0
            } else {
                currentTargetProgress = FoldMath.progress(angle: angle, clearAngle: clearAngle)
            }
            
            if currentTargetProgress > 0.03 {
                if !isCurrentlyVisible {
                    showOverlay()
                }
                metalView?.isPaused = false
                if let metalView = metalView {
                    renderer?.draw(in: metalView)
                }
            } else if isCurrentlyVisible {
                dismissFold()
            }
        } else {
            currentTargetProgress = 0.0
            if isCurrentlyVisible {
                dismissFold()
            }
        }
    }
    
    public func showOverlay() {
        guard let panel = overlayPanel, let screen = NSScreen.main else { return }
        let screenW = Int(screen.frame.width)
        let screenH = Int(screen.frame.height)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        
        if CGPreflightScreenCaptureAccess() {
            Task {
                do {
                    try await capture.start(displayID: displayID, width: screenW, height: screenH, fps: 60)
                } catch {
                    // 静默降级到壁纸底图渲染，不报错不阻塞
                }
            }
        }
        
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        // 严禁调用 makeKey()！让键盘焦点保持在用户当前的活跃应用中
        metalView?.isPaused = false
        isCurrentlyVisible = true
    }
    
    public func dismissFold() {
        demoTimer?.invalidate()
        demoTimer = nil
        isDemoRunning = false
        overlayPanel?.orderOut(nil)
        overlayPanel?.alphaValue = 0.0
        metalView?.isPaused = true
        isCurrentlyVisible = false
        renderer?.resetProgress(to: 0)
        currentTargetProgress = 0.0
        
        capture.stop()
    }
    
    public func manualDemoSequence() {
        demoTimer?.invalidate()
        isDemoRunning = true
        showOverlay()
        renderer?.resetProgress(to: 0)
        
        var elapsed: Double = 0.0
        let totalDuration: Double = 4.5
        let interval: Double = 1.0 / 60.0
        
        demoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            elapsed += interval
            let t = elapsed / totalDuration
            if t >= 1.0 {
                timer.invalidate()
                self.dismissFold()
                return
            }
            
            let p = sin(t * .pi) * 0.85
            self.currentTargetProgress = p
            self.metalView?.isPaused = false
            if let metalView = self.metalView {
                self.renderer?.draw(in: metalView)
            }
        }
    }
}
