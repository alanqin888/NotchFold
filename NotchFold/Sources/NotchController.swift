import Cocoa
import QuartzCore

// ─── 物理刘海屏幕精确探测器 ───
public final class NotchScreenManager {
    public static func getNotchScreen() -> NSScreen {
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return s
        }
        for s in NSScreen.screens {
            if let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                if CGDisplayIsBuiltin(num.uint32Value) != 0 {
                    return s
                }
            }
        }
        return NSScreen.screens.first ?? NSScreen.main!
    }
    
    public static func getNotchMetrics() -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, screen: NSScreen) {
        let s = getNotchScreen()
        let notchH = s.safeAreaInsets.top > 0 ? s.safeAreaInsets.top : 38.0
        let notchLeft = s.auxiliaryTopLeftArea?.maxX ?? (s.frame.origin.x + (s.frame.width - 220.0) / 2.0)
        let notchRight = s.auxiliaryTopRightArea?.minX ?? (notchLeft + 220.0)
        let notchW = max(200.0, notchRight - notchLeft)
        
        let x = notchLeft
        let y = s.frame.origin.y + s.frame.height - notchH
        return (x, y, notchW, notchH, s)
    }
}

// ─── 穿透点击的纯展示文本标签（避免遮挡按钮或磁贴的点击）───
public final class NonInteractiveLabel: NSTextField {
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// ─── 允许获取键盘焦点的专属刘海面板（解决“输入不进去”的问题）───
public final class NotchPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
    public override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
        super.mouseDown(with: event)
    }
    
    public override func cancelOperation(_ sender: Any?) {
        NotchController.shared.collapse()
    }
    
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// ─── 像素级垂直居中、无错位的高端胶囊按钮 ───
public class ModernPillButton: NSButton {
    private var actionClosure: (() -> Void)?
    private var isHovered = false
    private var normalBg: NSColor
    private var hoverBg: NSColor
    
    public init(title: String, tooltip: String = "", fontSize: CGFloat = 11.5, isDestructive: Bool = false, isAccent: Bool = false, action: @escaping () -> Void) {
        self.actionClosure = action
        if isDestructive {
            self.normalBg = NSColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 0.25)
            self.hoverBg = NSColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 0.45)
        } else if isAccent {
            self.normalBg = NSColor(red: 0.10, green: 0.50, blue: 0.95, alpha: 0.25)
            self.hoverBg = NSColor(red: 0.15, green: 0.60, blue: 1.0, alpha: 0.40)
        } else {
            self.normalBg = NSColor(white: 0.18, alpha: 0.55)
            self.hoverBg = NSColor(white: 0.28, alpha: 0.80)
        }
        
        super.init(frame: .zero)
        self.target = self
        self.action = #selector(buttonClicked)
        self.toolTip = tooltip
        self.isBordered = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 14
        self.layer?.cornerCurve = .continuous
        self.layer?.backgroundColor = normalBg.cgColor
        self.layer?.borderWidth = 0.8
        self.layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        
        setCenteredTitle(title, fontSize: fontSize)
        
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public func setAccent(_ accent: Bool) {
        if accent {
            self.normalBg = NSColor(red: 0.10, green: 0.50, blue: 0.95, alpha: 0.35)
            self.hoverBg = NSColor(red: 0.15, green: 0.60, blue: 1.0, alpha: 0.55)
        } else {
            self.normalBg = NSColor(white: 0.18, alpha: 0.55)
            self.hoverBg = NSColor(white: 0.28, alpha: 0.80)
        }
        self.layer?.backgroundColor = isHovered ? hoverBg.cgColor : normalBg.cgColor
    }
    
    public func setCenteredTitle(_ text: String, fontSize: CGFloat = 11.5) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor(white: 0.92, alpha: 1.0),
            .paragraphStyle: style
        ]
        self.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }
    
    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = hoverBg.cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.24).cgColor
    }
    
    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = normalBg.cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
    }
    
    @objc private func buttonClicked() {
        actionClosure?()
    }
}

// ─── 幽灵微边框操作按钮（清空等低优先级操作）───
public class GhostActionButton: NSButton {
    private var actionClosure: (() -> Void)?
    private var isHovered = false
    private let titleText: String
    
    public init(title: String, tooltip: String = "", action: @escaping () -> Void) {
        self.actionClosure = action
        self.titleText = title
        super.init(frame: .zero)
        self.target = self
        self.action = #selector(buttonClicked)
        self.toolTip = tooltip
        self.isBordered = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 7
        self.layer?.cornerCurve = .continuous
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.layer?.borderWidth = 0.8
        self.layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        
        updateTitle()
        
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func updateTitle() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: isHovered ? NSColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 0.95) : NSColor(white: 0.55, alpha: 1.0),
            .paragraphStyle: style
        ]
        self.attributedTitle = NSAttributedString(string: titleText, attributes: attrs)
    }
    
    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.08).cgColor
        layer?.borderColor = NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.30).cgColor
        updateTitle()
    }
    
    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        updateTitle()
    }
    
    @objc private func buttonClicked() {
        actionClosure?()
    }
}

// ─── 柔蓝微光主操作按钮（存入备忘录）───
public class AccentActionButton: NSButton {
    private var actionClosure: (() -> Void)?
    private var isHovered = false
    private let titleText: String
    
    public init(title: String, tooltip: String = "", action: @escaping () -> Void) {
        self.actionClosure = action
        self.titleText = title
        super.init(frame: .zero)
        self.target = self
        self.action = #selector(buttonClicked)
        self.toolTip = tooltip
        self.isBordered = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 7
        self.layer?.cornerCurve = .continuous
        self.layer?.backgroundColor = NSColor(red: 0.05, green: 0.45, blue: 0.95, alpha: 0.22).cgColor
        self.layer?.borderWidth = 0.8
        self.layer?.borderColor = NSColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.45).cgColor
        
        updateTitle()
        
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func updateTitle() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: isHovered ? NSColor.white : NSColor(red: 0.45, green: 0.82, blue: 1.0, alpha: 1.0),
            .paragraphStyle: style
        ]
        self.attributedTitle = NSAttributedString(string: titleText, attributes: attrs)
    }
    
    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.45, blue: 0.95, alpha: 0.38).cgColor
        layer?.borderColor = NSColor(red: 0.20, green: 0.65, blue: 1.0, alpha: 0.65).cgColor
        updateTitle()
    }
    
    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.45, blue: 0.95, alpha: 0.22).cgColor
        layer?.borderColor = NSColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.45).cgColor
        updateTitle()
    }
    
    @objc private func buttonClicked() {
        actionClosure?()
    }
}

// ─── 顶栏中央微晶状态药丸（整合传感器角度与流体效果快速切换）───
public final class CenterStatusCapsule: NSView {
    public var onEffectChanged: ((FoldEffect) -> Void)?
    private var angle: Double = 105.0
    private let statusDot = CALayer()
    private let textLabel = NSTextField()
    private var isHovered = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.6).cgColor
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        
        statusDot.backgroundColor = NSColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1.0).cgColor
        statusDot.cornerRadius = 3.5
        layer?.addSublayer(statusDot)
        
        textLabel.isBezeled = false
        textLabel.drawsBackground = false
        textLabel.isEditable = false
        textLabel.isSelectable = false
        addSubview(textLabel)
        
        updateDisplay()
        
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public override func layout() {
        super.layout()
        statusDot.frame = CGRect(x: 10, y: (bounds.height - 7) / 2.0, width: 7, height: 7)
        textLabel.frame = CGRect(x: 23, y: (bounds.height - 18) / 2.0, width: bounds.width - 28, height: 18)
    }
    
    public func setAngle(_ newAngle: Double) {
        self.angle = newAngle
        updateDisplay()
    }
    
    public func updateDisplay() {
        let effName = AppConfig.shared.selectedEffect.rawValue.capitalized
        let attr = NSMutableAttributedString()
        
        let angleStr = NSAttributedString(
            string: String(format: "铰链 %.0f°", angle),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor(white: 0.85, alpha: 1.0)
            ]
        )
        let dotStr = NSAttributedString(
            string: " · ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(white: 0.4, alpha: 1.0)
            ]
        )
        let effStr = NSAttributedString(
            string: "\(effName) ▾",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1.0)
            ]
        )
        
        attr.append(angleStr)
        attr.append(dotStr)
        attr.append(effStr)
        textLabel.attributedStringValue = attr
    }
    
    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        layer?.backgroundColor = NSColor(white: 0.24, alpha: 0.85).cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.28).cgColor
    }
    
    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.6).cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
    }
    
    public override func mouseDown(with event: NSEvent) {
        let all: [FoldEffect] = [.flex, .duo, .roll, .shutter, .iris]
        let cur = AppConfig.shared.selectedEffect
        if let idx = all.firstIndex(of: cur) {
            let next = all[(idx + 1) % all.count]
            AppConfig.shared.selectedEffect = next
            updateDisplay()
            onEffectChanged?(next)
            NSSound.beep()
        }
    }
}

public final class NotchController: NSObject {
    public static let shared = NotchController()
    
    private var notchWindow: NotchPanel?
    private var notchContainerView: NotchUnifiedView?
    private var statusItem: NSStatusItem?
    
    public private(set) var isExpanded = false
    
    // 全局与本地鼠标移动监听（实现物理刘海悬停展开 + 移出平滑收起）
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hoverExpandTimer: Timer?
    private var hoverCollapseTimer: Timer?
    
    private override init() {
        super.init()
    }
    
    deinit {
        if let g = globalMouseMonitor { NSEvent.removeMonitor(g) }
        if let l = localMouseMonitor { NSEvent.removeMonitor(l) }
    }
    
    public func setup() {
        createUnifiedNotchWindow()
        createStatusItem()
        setupMouseTracking()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    private func setupMouseTracking() {
        // 全局监控（在其他应用处于前台时生效）
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouseMoved(NSEvent.mouseLocation)
        }
        // 本地监控（在本应用激活前台时生效）
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved(NSEvent.mouseLocation)
            return event
        }
    }
    
    public func handleMouseMoved(_ mouseLoc: NSPoint) {
        let m = NotchScreenManager.getNotchMetrics()
        
        if !isExpanded {
            // 处于收起状态：检测鼠标是否移入物理刘海区域
            // 刘海探测区域：左右外延 16pt，下方外延 12pt，上方紧贴屏幕顶端
            let notchTriggerZone = CGRect(
                x: m.x - 16,
                y: m.screen.frame.maxY - m.height - 12,
                width: m.width + 32,
                height: m.height + 24
            )
            
            if notchTriggerZone.contains(mouseLoc) {
                hoverCollapseTimer?.invalidate()
                hoverCollapseTimer = nil
                
                if hoverExpandTimer == nil {
                    hoverExpandTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
                        self?.hoverExpandTimer = nil
                        guard let self = self, !self.isExpanded else { return }
                        let currentLoc = NSEvent.mouseLocation
                        let currentMetrics = NotchScreenManager.getNotchMetrics()
                        let checkZone = CGRect(
                            x: currentMetrics.x - 20,
                            y: currentMetrics.screen.frame.maxY - currentMetrics.height - 16,
                            width: currentMetrics.width + 40,
                            height: currentMetrics.height + 30
                        )
                        if checkZone.contains(currentLoc) {
                            self.expand()
                        }
                    }
                }
            } else {
                hoverExpandTimer?.invalidate()
                hoverExpandTimer = nil
            }
        } else {
            // 处于展开状态：检测鼠标是否移出 740x540 面板
            guard let panel = notchWindow else { return }
            // 面板边界提供 20pt 缓冲保护，避免在面板边缘移动时误触收起
            let panelZone = panel.frame.insetBy(dx: -20, dy: -20)
            
            if panelZone.contains(mouseLoc) {
                // 鼠标在面板内：重置收起计时器
                hoverCollapseTimer?.invalidate()
                hoverCollapseTimer = nil
            } else {
                // 鼠标移出面板：延迟 0.35 秒平滑收起
                if hoverCollapseTimer == nil {
                    hoverCollapseTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                        self?.hoverCollapseTimer = nil
                        guard let self = self, self.isExpanded, let p = self.notchWindow else { return }
                        let currentLoc = NSEvent.mouseLocation
                        let checkZone = p.frame.insetBy(dx: -12, dy: -12)
                        if !checkZone.contains(currentLoc) {
                            self.collapse()
                        }
                    }
                }
            }
        }
    }
    
    @objc private func screenParametersChanged() {
        updateWindowPosition()
    }
    
    private func createUnifiedNotchWindow() {
        let m = NotchScreenManager.getNotchMetrics()
        
        let compactW: CGFloat = m.width + 4
        let compactH: CGFloat = m.height + 2
        let compactX = m.x - 2
        let compactY = m.screen.frame.origin.y + m.screen.frame.height - compactH
        
        // 使用自定义 NotchPanel (canBecomeKey=true)，彻底去除 nonactivatingPanel 限制
        let panel = NotchPanel(
            contentRect: CGRect(x: compactX, y: compactY, width: compactW, height: compactH),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar + 3
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        let unifiedView = NotchUnifiedView(frame: panel.contentView!.bounds)
        unifiedView.autoresizingMask = [.width, .height]
        unifiedView.onToggle = { [weak self] in
            self?.toggle()
        }
        panel.contentView = unifiedView
        self.notchContainerView = unifiedView
        self.notchWindow = panel
        
        panel.makeKeyAndOrderFront(nil)
    }
    
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            let iconImage = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                // 绘制极客刘海与折叠屏拟态微图标
                let outline = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 3.5, width: 13, height: 11), xRadius: 2.5, yRadius: 2.5)
                outline.lineWidth = 1.2
                NSColor.labelColor.setStroke()
                outline.stroke()
                
                // 顶部刘海特征
                let notchPath = NSBezierPath(roundedRect: NSRect(x: 6.5, y: 10.5, width: 5, height: 3.5), xRadius: 1, yRadius: 1)
                NSColor.labelColor.setFill()
                notchPath.fill()
                
                // 中轴折痕微线
                let foldLine = NSBezierPath()
                foldLine.move(to: NSPoint(x: 2.5, y: 8.5))
                foldLine.line(to: NSPoint(x: 15.5, y: 8.5))
                foldLine.lineWidth = 0.8
                foldLine.stroke()
                return true
            }
            iconImage.isTemplate = true
            btn.image = iconImage
            btn.title = ""
            btn.toolTip = "NotchFold 刘海中心 (左键展开/收起 · 右键菜单/退出)"
            btn.target = self
            btn.action = #selector(statusItemClicked)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusContextMenu()
        } else {
            toggle()
        }
    }
    
    @objc public func showStatusContextMenu() {
        let menu = NSMenu()
        
        let toggleTitle = isExpanded ? "收起刘海面板" : "展开刘海面板"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(menuToggleAction), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let demoItem = NSMenuItem(title: "全屏光学折叠演练 (5秒)", action: #selector(menuDemoAction), keyEquivalent: "")
        demoItem.target = self
        menu.addItem(demoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let editItem = NSMenuItem(title: "管理快捷应用 / 文件夹...", action: #selector(menuManageAction), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 NotchFold", action: #selector(menuQuitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }
    
    @objc private func menuToggleAction() {
        toggle()
    }
    
    @objc private func menuDemoAction() {
        if isExpanded { collapse() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            FoldWindowController.shared.manualDemoSequence()
        }
    }
    
    @objc private func menuManageAction() {
        if !isExpanded { expand() }
        notchContainerView?.toggleEditMode()
    }
    
    @objc private func menuQuitAction() {
        NSApp.terminate(nil)
    }
    
    public func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }
    
    public func expand() {
        guard let panel = notchWindow, let view = notchContainerView else { return }
        hoverExpandTimer?.invalidate()
        hoverExpandTimer = nil
        hoverCollapseTimer?.invalidate()
        hoverCollapseTimer = nil
        isExpanded = true
        
        let m = NotchScreenManager.getNotchMetrics()
        let s = m.screen
        
        let expandedW: CGFloat = 680
        let expandedH: CGFloat = 390
        let targetX = s.frame.origin.x + (s.frame.width - expandedW) / 2.0
        let targetY = s.frame.origin.y + s.frame.height - expandedH
        let targetFrame = CGRect(x: targetX, y: targetY, width: expandedW, height: expandedH)
        
        panel.hasShadow = false
        view.prepareForExpansion(targetSize: CGSize(width: expandedW, height: expandedH))
        
        // 关键：激活应用与面板焦点，确保随手记输入框光标立现并接收打字输入
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
            view.finishExpansion()
        }
    }
    
    public func collapse() {
        guard let panel = notchWindow, let view = notchContainerView else { return }
        hoverExpandTimer?.invalidate()
        hoverExpandTimer = nil
        hoverCollapseTimer?.invalidate()
        hoverCollapseTimer = nil
        isExpanded = false
        
        let m = NotchScreenManager.getNotchMetrics()
        let compactW: CGFloat = m.width + 4
        let compactH: CGFloat = m.height + 2
        let compactX = m.x - 2
        let compactY = m.screen.frame.origin.y + m.screen.frame.height - compactH
        let targetFrame = CGRect(x: compactX, y: compactY, width: compactW, height: compactH)
        
        view.prepareForCollapse()
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            panel.hasShadow = false
            view.finishCollapse()
            panel.resignKey()
        }
    }
    
    private func updateWindowPosition() {
        guard let panel = notchWindow else { return }
        let m = NotchScreenManager.getNotchMetrics()
        if isExpanded {
            let expandedW: CGFloat = 680
            let expandedH: CGFloat = 390
            let targetX = m.screen.frame.origin.x + (m.screen.frame.width - expandedW) / 2.0
            let targetY = m.screen.frame.origin.y + m.screen.frame.height - expandedH
            panel.setFrame(CGRect(x: targetX, y: targetY, width: expandedW, height: expandedH), display: true)
        } else {
            let compactW: CGFloat = m.width + 4
            let compactH: CGFloat = m.height + 2
            let compactX = m.x - 2
            let compactY = m.screen.frame.origin.y + m.screen.frame.height - compactH
            panel.setFrame(CGRect(x: compactX, y: compactY, width: compactW, height: compactH), display: true)
        }
    }
    
    public func updateAngleDisplay(_ angle: Double) {
        notchContainerView?.updateAngle(angle)
    }
}

// ─── NotchNook 风格横向平滑滚动图标托盘（App Tray）───
public final class NotchAppTrayView: NSView {
    public var onDropURL: ((URL) -> Void)?
    public var onItemClick: ((CustomShortcut) -> Void)?
    public var onAddClicked: ((NSView) -> Void)?
    public var onDeleteItem: ((String) -> Void)?
    public var isEditMode: Bool = false {
        didSet { reloadData() }
    }
    
    private let titleLabel = NSTextField(labelWithString: "快捷入口 (APP TRAY)")
    private let hintLabel = NSTextField(labelWithString: "横向滑动 · 拖入应用/文件夹添加")
    
    private let scrollView = NSScrollView()
    private let shelfContainer = NSView()
    private let dropBorderLayer = CAShapeLayer()
    private var isDragOver = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL])
        wantsLayer = true
        setupViews()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public override var isFlipped: Bool { return false }
    
    private func setupViews() {
        titleLabel.font = NSFont.systemFont(ofSize: 10.0, weight: .semibold)
        titleLabel.textColor = NSColor(white: 0.45, alpha: 1.0)
        addSubview(titleLabel)
        
        hintLabel.font = NSFont.systemFont(ofSize: 9.0, weight: .regular)
        hintLabel.textColor = NSColor(white: 0.35, alpha: 1.0)
        hintLabel.alignment = .right
        addSubview(hintLabel)
        
        // 配置横向滚动容器
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = shelfContainer
        addSubview(scrollView)
        
        // 拖拽高亮描边
        dropBorderLayer.strokeColor = NSColor(red: 0.15, green: 0.65, blue: 1.0, alpha: 0.95).cgColor
        dropBorderLayer.fillColor = NSColor(red: 0.1, green: 0.5, blue: 1.0, alpha: 0.12).cgColor
        dropBorderLayer.lineWidth = 1.5
        dropBorderLayer.lineDashPattern = [5, 3]
        dropBorderLayer.isHidden = true
        layer?.addSublayer(dropBorderLayer)
    }
    
    public override func layout() {
        super.layout()
        let r = bounds
        titleLabel.frame = CGRect(x: 2, y: r.height - 15, width: 140, height: 14)
        hintLabel.frame = CGRect(x: 140, y: r.height - 15, width: r.width - 142, height: 14)
        
        let trayH: CGFloat = 66
        scrollView.frame = CGRect(x: 0, y: 0, width: r.width, height: trayH)
        
        dropBorderLayer.frame = CGRect(x: 0, y: 0, width: r.width, height: trayH)
        let path = CGPath(roundedRect: dropBorderLayer.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 12, cornerHeight: 12, transform: nil)
        dropBorderLayer.path = path
        
        reloadData()
    }
    
    public func reloadData() {
        shelfContainer.subviews.forEach { $0.removeFromSuperview() }
        let items = AppConfig.shared.shortcuts
        
        let itemW: CGFloat = 52
        let gap: CGFloat = 10
        let shelfH: CGFloat = 66
        let totalCount = items.count + 1 // items + add button
        let totalContentW = max(bounds.width, CGFloat(totalCount) * (itemW + gap) + 12)
        
        shelfContainer.frame = CGRect(x: 0, y: 0, width: totalContentW, height: shelfH)
        
        for (i, item) in items.enumerated() {
            let posX = CGFloat(i) * (itemW + gap) + 4
            let card = createTrayItem(item: item, frame: CGRect(x: posX, y: 0, width: itemW, height: shelfH))
            shelfContainer.addSubview(card)
        }
        
        // 托盘末尾常驻：＋ 添加按钮
        let addX = CGFloat(items.count) * (itemW + gap) + 4
        let addCard = createAddTrayItem(frame: CGRect(x: addX, y: 0, width: itemW, height: shelfH))
        shelfContainer.addSubview(addCard)
    }
    
    private func createTrayItem(item: CustomShortcut, frame: CGRect) -> NSView {
        let container = NSView(frame: frame)
        
        let iconBtn = ClosureButton(frame: CGRect(x: (frame.width - 40) / 2.0, y: 22, width: 40, height: 40)) { [weak self] in
            if self?.isEditMode == false {
                self?.onItemClick?(item)
            }
        }
        iconBtn.wantsLayer = true
        iconBtn.layer?.cornerRadius = 10
        iconBtn.layer?.cornerCurve = .continuous
        iconBtn.layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.70).cgColor
        iconBtn.layer?.borderWidth = 0.6
        iconBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        iconBtn.toolTip = "\(item.name) (\(item.displaySubtitle))"
        
        iconBtn.onHover = { [weak iconBtn] h in
            if h {
                iconBtn?.layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.90).cgColor
                iconBtn?.layer?.borderColor = NSColor(white: 1.0, alpha: 0.28).cgColor
            } else {
                iconBtn?.layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.70).cgColor
                iconBtn?.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
            }
        }
        container.addSubview(iconBtn)
        
        let icon = NSWorkspace.shared.icon(forFile: item.path)
        icon.size = NSSize(width: 26, height: 26)
        let imgView = NSImageView(frame: CGRect(x: 7, y: 7, width: 26, height: 26))
        imgView.image = icon
        iconBtn.addSubview(imgView)
        
        let label = NonInteractiveLabel(labelWithString: item.name)
        label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(white: 0.85, alpha: 1.0)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = CGRect(x: 0, y: 3, width: frame.width, height: 14)
        container.addSubview(label)
        
        if isEditMode {
            let del = NSButton()
            del.title = "✕"
            del.bezelStyle = .circular
            del.wantsLayer = true
            del.contentTintColor = .white
            del.layer?.backgroundColor = NSColor.systemRed.cgColor
            del.frame = CGRect(x: frame.width - 16, y: frame.height - 18, width: 14, height: 14)
            del.font = NSFont.systemFont(ofSize: 8, weight: .bold)
            del.action = #selector(deleteClicked(_:))
            del.target = self
            del.identifier = NSUserInterfaceItemIdentifier(item.id)
            container.addSubview(del)
        }
        
        return container
    }
    
    private func createAddTrayItem(frame: CGRect) -> NSView {
        let container = NSView(frame: frame)
        
        let addBtn = ClosureButton(frame: CGRect(x: (frame.width - 40) / 2.0, y: 22, width: 40, height: 40)) { [weak self, weak container] in
            guard let self = self, let c = container else { return }
            self.onAddClicked?(c)
        }
        addBtn.wantsLayer = true
        addBtn.layer?.cornerRadius = 10
        addBtn.layer?.cornerCurve = .continuous
        addBtn.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.40).cgColor
        addBtn.layer?.borderWidth = 0.8
        addBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        addBtn.toolTip = "添加常用应用或文件夹"
        
        addBtn.onHover = { [weak addBtn] h in
            if h {
                addBtn?.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.70).cgColor
                addBtn?.layer?.borderColor = NSColor(red: 0.2, green: 0.65, blue: 1.0, alpha: 0.6).cgColor
            } else {
                addBtn?.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.40).cgColor
                addBtn?.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
            }
        }
        container.addSubview(addBtn)
        
        let plusLabel = NonInteractiveLabel(labelWithString: "＋")
        plusLabel.font = NSFont.systemFont(ofSize: 18, weight: .light)
        plusLabel.textColor = NSColor(white: 0.50, alpha: 1.0)
        plusLabel.alignment = .center
        plusLabel.frame = CGRect(x: 0, y: 8, width: 40, height: 24)
        addBtn.addSubview(plusLabel)
        
        let label = NonInteractiveLabel(labelWithString: "添加")
        label.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor(white: 0.45, alpha: 1.0)
        label.alignment = .center
        label.frame = CGRect(x: 0, y: 3, width: frame.width, height: 14)
        container.addSubview(label)
        
        return container
    }
    
    @objc private func deleteClicked(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue {
            onDeleteItem?(id)
        }
    }
    
    // 拖拽处理
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let pasteboard = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !pasteboard.isEmpty {
            isDragOver = true
            dropBorderLayer.isHidden = false
            return .copy
        }
        return []
    }
    
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return isDragOver ? .copy : []
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragOver = false
        dropBorderLayer.isHidden = true
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragOver = false
        dropBorderLayer.isHidden = true
        guard let pasteboard = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let firstURL = pasteboard.first else { return false }
        onDropURL?(firstURL)
        return true
    }
}

// ─── 统一刘海灵动岛视图（支持鼠标悬停自动展开、离开自动收起）───
public final class NotchUnifiedView: NSView {
    public var onToggle: (() -> Void)?
    
    // 纯黑物理底色指示条（收起时的小白条）
    private let capsuleIndicator = CALayer()
    
    private let contentContainer = NSView()
    private var isEditMode = false
    private var trackingAreaRef: NSTrackingArea?
    
    private let leftWingView = NSView()
    private let rightWingView = NSView()
    private let statusCapsule = CenterStatusCapsule()
    
    private let appTray = NotchAppTrayView()
    private let scratchpadView = NotchScratchpadView()
    private let footerLabel = NSTextField(labelWithString: "🟢 Apple Silicon 物理传感器就绪 · 移出/Esc 收起 · ⌘Q 退出程序")
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        setupPureBlackAppearance()
        setupContentHierarchy()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public override var isFlipped: Bool { return false }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let t = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }
    
    public override func mouseEntered(with event: NSEvent) {
        NotchController.shared.handleMouseMoved(NSEvent.mouseLocation)
    }
    
    public override func mouseExited(with event: NSEvent) {
        NotchController.shared.handleMouseMoved(NSEvent.mouseLocation)
    }
    
    public override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        super.mouseDown(with: event)
    }
    
    public override func cancelOperation(_ sender: Any?) {
        NotchController.shared.collapse()
    }
    
    private func setupPureBlackAppearance() {
        wantsLayer = true
        guard let root = layer else { return }
        
        // 1. 根图层纯黑物理底色（100% 纯黑，与物理刘海与边框浑然一体，彻底消除上边框亮线与浮动感）
        root.backgroundColor = NSColor.black.cgColor
        root.cornerRadius = 26
        root.cornerCurve = .continuous
        root.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        root.borderWidth = 0.0
        root.borderColor = nil
        
        // 2. 收起状态小白条指示器
        root.addSublayer(capsuleIndicator)
        capsuleIndicator.backgroundColor = NSColor(white: 1.0, alpha: 0.45).cgColor
        capsuleIndicator.cornerRadius = 2
        
        addSubview(contentContainer)
        contentContainer.alphaValue = 0.0
        contentContainer.isHidden = true
    }
    
    public override func layout() {
        super.layout()
        let r = bounds
        layer?.cornerRadius = r.height > 100 ? 26 : 10
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        
        capsuleIndicator.frame = CGRect(x: (r.width - 36) / 2.0, y: 8, width: 36, height: 4)
        
        contentContainer.frame = r
        layoutWingsAndContent()
    }
    
    private func setupContentHierarchy() {
        contentContainer.addSubview(leftWingView)
        contentContainer.addSubview(statusCapsule)
        contentContainer.addSubview(rightWingView)
        
        // 左翼功能按钮（微晶磨砂胶囊）
        let shotArea = ModernPillButton(title: "📸 选区截图", tooltip: "框选屏幕区域保存到桌面") { [weak self] in
            self?.onToggle?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                AppConfig.triggerScreenshot(mode: .interactive)
            }
        }
        shotArea.frame = CGRect(x: 0, y: 0, width: 96, height: 28)
        leftWingView.addSubview(shotArea)
        
        let shotClip = ModernPillButton(title: "📋 复制截屏", tooltip: "截取屏幕并拷贝到剪贴板") { [weak self] in
            self?.onToggle?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                AppConfig.triggerScreenshot(mode: .toClipboard)
            }
        }
        shotClip.frame = CGRect(x: 104, y: 0, width: 96, height: 28)
        leftWingView.addSubview(shotClip)
        
        // 右翼功能按钮
        let foldDemo = ModernPillButton(title: "🌀 演练", tooltip: "全屏运行 5 秒 Metal 流体折叠演练") { [weak self] in
            self?.onToggle?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                FoldWindowController.shared.manualDemoSequence()
            }
        }
        foldDemo.frame = CGRect(x: 0, y: 0, width: 78, height: 28)
        rightWingView.addSubview(foldDemo)
        
        let editBtn = ModernPillButton(title: "⚙️ 管理", tooltip: "管理快捷方式 / 退出程序") { [weak self] in
            guard let self = self else { return }
            self.showManagementMenu(from: self.rightWingView)
        }
        editBtn.frame = CGRect(x: 84, y: 0, width: 74, height: 28)
        rightWingView.addSubview(editBtn)
        
        let closeBtn = ModernPillButton(title: "✕", tooltip: "收起刘海面板 (Esc 收起 · ⌘Q 退出程序)") { [weak self] in
            self?.onToggle?()
        }
        closeBtn.frame = CGRect(x: 164, y: 0, width: 34, height: 28)
        rightWingView.addSubview(closeBtn)
        
        // 上层：快捷图标托盘
        appTray.onDropURL = { [weak self] url in
            if let _ = AppConfig.shared.addFromDroppedURL(url) {
                self?.appTray.reloadData()
                NSSound.beep()
            }
        }
        appTray.onItemClick = { [weak self] item in
            AppConfig.openItem(item)
            self?.onToggle?()
        }
        appTray.onAddClicked = { [weak self] view in
            self?.showAddMenu(from: view)
        }
        appTray.onDeleteItem = { [weak self] id in
            AppConfig.shared.removeShortcut(id: id)
            self?.appTray.reloadData()
        }
        contentContainer.addSubview(appTray)
        
        // 下层：全宽随手记
        contentContainer.addSubview(scratchpadView)
        
        // 底部微条
        footerLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        footerLabel.textColor = NSColor(white: 0.40, alpha: 1.0)
        footerLabel.alignment = .center
        contentContainer.addSubview(footerLabel)
    }
    
    private func layoutWingsAndContent() {
        let r = bounds
        if r.height < 100 { return }
        
        let padX: CGFloat = 16
        let totalW = r.width - padX * 2
        let wingW: CGFloat = 204
        let topBarH: CGFloat = 28
        
        // 1. 顶部翼展行：直面物理刘海，位于顶端刘海高度内（避开中央 220pt 硬件摄像头禁区）
        let wingY = r.height - topBarH - 4
        leftWingView.frame = CGRect(x: padX, y: wingY, width: wingW, height: topBarH)
        rightWingView.frame = CGRect(x: r.width - padX - wingW, y: wingY, width: wingW, height: topBarH)
        
        // 2. 硬件开合角度与流体切换微晶药丸（紧贴物理刘海 38pt 下方居中）
        let notchH: CGFloat = 38
        let statusH: CGFloat = 26
        let statusY = r.height - notchH - statusH - 4
        statusCapsule.frame = CGRect(x: (r.width - 164) / 2.0, y: statusY, width: 164, height: statusH)
        
        // 3. 上层：应用图标平滑滚动托盘 (APP TRAY)
        let trayH: CGFloat = 84
        let trayY = statusY - 8 - trayH
        appTray.frame = CGRect(x: padX, y: trayY, width: totalW, height: trayH)
        
        // 4. 下层：全宽沉浸式随手记 (SCRATCHPAD)
        let scratchpadBottom: CGFloat = 26
        let scratchpadH = trayY - 10 - scratchpadBottom
        scratchpadView.frame = CGRect(x: padX, y: scratchpadBottom, width: totalW, height: scratchpadH)
        
        // 5. 底部居中微条
        footerLabel.frame = CGRect(x: 20, y: 6, width: r.width - 40, height: 14)
    }
    
    private func showAddMenu(from sourceView: NSView) {
        let menu = NSMenu()
        let appItem = NSMenuItem(title: "＋ 添加常用应用...", action: #selector(menuAddAppClicked), keyEquivalent: "")
        appItem.target = self
        menu.addItem(appItem)
        
        let folderItem = NSMenuItem(title: "＋ 添加常用文件夹...", action: #selector(menuAddFolderClicked), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
        
        let point = NSPoint(x: sourceView.bounds.midX, y: 0)
        menu.popUp(positioning: nil, at: point, in: sourceView)
    }
    
    @objc private func menuAddAppClicked() {
        pickApp()
    }
    
    @objc private func menuAddFolderClicked() {
        pickFolder()
    }
    
    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "选择常用应用"
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let u = panel.url {
            AppConfig.shared.addShortcut(name: u.deletingPathExtension().lastPathComponent, path: u.path, subtitle: "自定义应用", isApp: true)
            appTray.reloadData()
        }
    }
    
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择常用文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let u = panel.url {
            AppConfig.shared.addShortcut(name: u.lastPathComponent, path: u.path, subtitle: "本地文件夹", isApp: false)
            appTray.reloadData()
        }
    }
    
    public func toggleEditMode() {
        isEditMode.toggle()
        appTray.isEditMode = isEditMode
    }
    
    private func showManagementMenu(from sourceView: NSView) {
        let menu = NSMenu()
        
        let editItem = NSMenuItem(title: isEditMode ? "✓ 完成快捷方式编辑" : "✏️ 编辑快捷方式 (增删图标)", action: #selector(menuToggleEditAction), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)
        
        let addItem = NSMenuItem(title: "＋ 添加应用或文件夹...", action: #selector(menuAddCustomAction), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let demoItem = NSMenuItem(title: "🌀 运行全屏折叠演练 (⌘⇧F)", action: #selector(menuDemoAction), keyEquivalent: "")
        demoItem.target = self
        menu.addItem(demoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "🚪 退出 NotchFold (⌘Q)", action: #selector(menuQuitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        let point = NSPoint(x: 84, y: 0)
        menu.popUp(positioning: nil, at: point, in: sourceView)
    }
    
    @objc private func menuToggleEditAction() {
        toggleEditMode()
    }
    
    @objc private func menuAddCustomAction() {
        showAddMenu(from: appTray)
    }
    
    @objc private func menuDemoAction() {
        onToggle?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            FoldWindowController.shared.manualDemoSequence()
        }
    }
    
    @objc private func menuQuitAction() {
        NSApp.terminate(nil)
    }
    
    public func updateAngle(_ angle: Double) {
        statusCapsule.setAngle(angle)
        footerLabel.stringValue = String(format: "NotchFold 硬件角度: %.0f° · 移出/Esc 收起 · ⌘Q 退出程序", angle)
    }
    
    public override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.height < 50 && loc.y < 45 {
            onToggle?()
        } else {
            super.mouseUp(with: event)
        }
    }
    
    public func prepareForExpansion(targetSize: CGSize) {
        capsuleIndicator.opacity = 0.0
    }
    
    public func finishExpansion() {
        contentContainer.isHidden = false
        contentContainer.alphaValue = 1.0
        scratchpadView.focusInput() // 展开后自动聚焦随手记输入框，支持直接输入
    }
    
    public func prepareForCollapse() {
        contentContainer.alphaValue = 0.0
        contentContainer.isHidden = true
    }
    
    public func finishCollapse() {
        capsuleIndicator.opacity = 1.0
        if isEditMode {
            toggleEditMode()
        }
    }
}

// ─── 允许打字、获得焦点并拦截 Esc 的专属文本框 ───
public final class ScratchpadTextView: NSTextView {
    public var onCommandEnter: (() -> Void)?
    public weak var scratchpadView: NotchScratchpadView?
    public override var acceptsFirstResponder: Bool { true }
    public override var canBecomeKeyView: Bool { true }
    
    public override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        super.mouseDown(with: event)
    }
    
    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // 单击链接立即在浏览器中打开
        if event.clickCount == 1 && selectedRange().length == 0 {
            let point = convert(event.locationInWindow, from: nil)
            let charIndex = characterIndexForInsertion(at: point)
            if charIndex < (textStorage?.length ?? 0) {
                if let link = textStorage?.attribute(.link, at: charIndex, effectiveRange: nil) {
                    if let url = link as? URL {
                        NSWorkspace.shared.open(url)
                    } else if let str = link as? String, let url = URL(string: str) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
    
    public override func cancelOperation(_ sender: Any?) {
        NotchController.shared.collapse()
    }
    
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.keyCode == 36 || event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\n" {
                if let cb = onCommandEnter {
                    cb()
                    return true
                }
            }
            if key == "v" {
                if let pad = scratchpadView, pad.handlePasteAction() {
                    return true
                }
            } else if key == "c" {
                copy(nil)
                return true
            } else if key == "a" {
                selectAll(nil)
                return true
            } else if key == "x" {
                cut(nil)
                return true
            } else if key == "z" {
                if flags.contains(.shift) {
                    undoManager?.redo()
                } else {
                    undoManager?.undo()
                }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        if charIndex < (textStorage?.length ?? 0),
           let link = textStorage?.attribute(.link, at: charIndex, effectiveRange: nil) {
            let targetURL: URL? = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
            if let u = targetURL {
                let openItem = NSMenuItem(title: "在新窗口打开链接", action: #selector(contextOpenLinkAction(_:)), keyEquivalent: "")
                openItem.representedObject = u
                openItem.target = self
                menu.addItem(openItem)
                menu.addItem(NSMenuItem.separator())
            }
        }
        
        menu.addItem(withTitle: "剪切", action: #selector(cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "拷贝", action: #selector(copy(_:)), keyEquivalent: "c")
        
        let pasteItem = NSMenuItem(title: "粘贴", action: #selector(contextPasteClicked), keyEquivalent: "v")
        pasteItem.target = self
        menu.addItem(pasteItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "全选", action: #selector(selectAll(_:)), keyEquivalent: "a")
        
        let clearItem = NSMenuItem(title: "清空随手记", action: #selector(contextClearClicked), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        
        return menu
    }
    
    @objc private func contextOpenLinkAction(_ sender: NSMenuItem) {
        if let u = sender.representedObject as? URL {
            NSWorkspace.shared.open(u)
        }
    }
    
    @objc private func contextPasteClicked() {
        scratchpadView?.handlePasteAction()
    }
    
    @objc private func contextClearClicked() {
        scratchpadView?.clearNote()
    }
}

// ─── 响应点击卡片聚焦输入框的背景容器 ───
public final class ScratchpadCardView: NSView {
    public var onClick: (() -> Void)?
    public override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }
}

// ─── 快速随手记（支持打字、直接 ⌘V 粘贴文字/截图、拖拽文件，仅清空与存备忘录新建两大功能）───
public final class NotchScratchpadView: NSView, NSTextViewDelegate {
    private let titleLabel = NSTextField(labelWithString: "随手记")
    private let hintLabel = NSTextField(labelWithString: "⌘V 贴图 · 拖入文件 · 自动留存")
    
    private let cardBackground = ScratchpadCardView()
    private let scrollView = NSScrollView()
    private let textView = ScratchpadTextView()
    
    private let placeholderLabel = NSTextField(labelWithString: "在此输入随手记内容，或按 ⌘V 直接贴入截图...")
    
    private let attachmentBar = NSView()
    private let attachmentIcon = NSImageView()
    private let attachmentNameLabel = NSTextField(labelWithString: "")
    private let attachmentRemoveBtn = NSButton()
    
    private var currentAttachmentPath: String?
    private let statusFeedbackLabel = NSTextField(labelWithString: "")
    
    private var deleteBtn: GhostActionButton?
    private var saveAddBtn: AccentActionButton?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupScratchpad()
        registerForDraggedTypes([.fileURL, .png, .tiff, .string])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public override var isFlipped: Bool { return false }
    
    private func setupScratchpad() {
        titleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        titleLabel.textColor = NSColor(white: 0.50, alpha: 1.0)
        addSubview(titleLabel)
        
        hintLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        hintLabel.textColor = NSColor(white: 0.40, alpha: 1.0)
        hintLabel.alignment = .right
        addSubview(hintLabel)
        
        cardBackground.wantsLayer = true
        cardBackground.layer?.cornerRadius = 14
        cardBackground.layer?.cornerCurve = .continuous
        cardBackground.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.82).cgColor
        cardBackground.layer?.borderWidth = 0.8
        cardBackground.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        cardBackground.onClick = { [weak self] in
            self?.focusInput()
        }
        addSubview(cardBackground)
        
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        // 配置输入框：确保支持键盘输入与纵向自适应伸展
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor.white
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.insertionPointColor = NSColor.white
        textView.isAutomaticLinkDetectionEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(red: 0.38, green: 0.68, blue: 1.0, alpha: 1.0),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        textView.delegate = self
        textView.scratchpadView = self
        textView.onCommandEnter = { [weak self] in
            self?.saveAndNewNote()
        }
        
        textView.minSize = NSSize(width: 0.0, height: 200)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        scrollView.documentView = textView
        cardBackground.addSubview(scrollView)
        
        // 占位提示文字
        placeholderLabel.font = NSFont.systemFont(ofSize: 12.5)
        placeholderLabel.textColor = NSColor(white: 0.35, alpha: 1.0)
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        cardBackground.addSubview(placeholderLabel)
        
        // 附件胶囊条（支持显示真实图片缩略图）
        attachmentBar.wantsLayer = true
        attachmentBar.layer?.cornerRadius = 8
        attachmentBar.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.90).cgColor
        attachmentBar.layer?.borderWidth = 1.0
        attachmentBar.layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
        attachmentBar.isHidden = true
        
        attachmentIcon.wantsLayer = true
        attachmentIcon.layer?.cornerRadius = 5
        attachmentIcon.layer?.masksToBounds = true
        attachmentIcon.imageScaling = .scaleProportionallyUpOrDown
        attachmentBar.addSubview(attachmentIcon)
        
        attachmentNameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        attachmentNameLabel.textColor = NSColor(white: 0.92, alpha: 1.0)
        attachmentNameLabel.lineBreakMode = .byTruncatingMiddle
        attachmentBar.addSubview(attachmentNameLabel)
        
        attachmentRemoveBtn.title = "✕"
        attachmentRemoveBtn.bezelStyle = .inline
        attachmentRemoveBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        attachmentRemoveBtn.target = self
        attachmentRemoveBtn.action = #selector(removeAttachmentClicked)
        attachmentBar.addSubview(attachmentRemoveBtn)
        cardBackground.addSubview(attachmentBar)
        
        // 底部极简双按键（幽灵清空 + 柔蓝微光存入备忘录）
        let del = GhostActionButton(title: "清空", tooltip: "清空当前随手记内容") { [weak self] in
            self?.clearNote()
        }
        addSubview(del)
        self.deleteBtn = del
        
        let save = AccentActionButton(title: "存入备忘录 ↵", tooltip: "保存到 Apple Notes 备忘录并开启全新空白页 (⌘+Enter)") { [weak self] in
            self?.saveAndNewNote()
        }
        addSubview(save)
        self.saveAddBtn = save
        
        statusFeedbackLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        statusFeedbackLabel.textColor = NSColor.systemGreen
        statusFeedbackLabel.alignment = .center
        statusFeedbackLabel.alphaValue = 0.0
        addSubview(statusFeedbackLabel)
    }
    
    public override func layout() {
        super.layout()
        let r = bounds
        titleLabel.frame = CGRect(x: 2, y: r.height - 18, width: 100, height: 16)
        hintLabel.frame = CGRect(x: 100, y: r.height - 18, width: r.width - 102, height: 16)
        
        let cardY: CGFloat = 36
        let cardH = r.height - 22 - cardY
        cardBackground.frame = CGRect(x: 0, y: cardY, width: r.width, height: cardH)
        
        if attachmentBar.isHidden {
            scrollView.frame = CGRect(x: 10, y: 10, width: r.width - 20, height: cardH - 20)
        } else {
            let barH: CGFloat = 36
            attachmentBar.frame = CGRect(x: 10, y: 10, width: r.width - 20, height: barH)
            attachmentIcon.frame = CGRect(x: 6, y: 4, width: 28, height: 28)
            attachmentNameLabel.frame = CGRect(x: 40, y: 8, width: r.width - 96, height: 20)
            attachmentRemoveBtn.frame = CGRect(x: r.width - 48, y: 7, width: 22, height: 22)
            
            scrollView.frame = CGRect(x: 10, y: barH + 16, width: r.width - 20, height: cardH - barH - 26)
        }
        
        if let tc = textView.textContainer {
            tc.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            tc.widthTracksTextView = true
        }
        textView.frame = CGRect(origin: .zero, size: scrollView.contentSize)
        placeholderLabel.frame = CGRect(x: 14, y: cardH - 32, width: r.width - 28, height: 20)
        
        let btnH: CGFloat = 28
        deleteBtn?.frame = CGRect(x: 0, y: 0, width: 64, height: btnH)
        saveAddBtn?.frame = CGRect(x: r.width - 136, y: 0, width: 136, height: btnH)
        statusFeedbackLabel.frame = CGRect(x: 74, y: 5, width: max(50, r.width - 74 - 146), height: 18)
    }
    
    public func focusInput() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(textView)
    }
    
    public override func mouseDown(with event: NSEvent) {
        focusInput()
        super.mouseDown(with: event)
    }
    
    public func textDidChange(_ notification: Notification) {
        placeholderLabel.isHidden = !textView.string.isEmpty
        textView.checkTextInDocument(nil)
    }
    
    public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL {
            NSWorkspace.shared.open(url)
            return true
        } else if let str = link as? String, let url = URL(string: str) {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }
    
    @objc private func removeAttachmentClicked() {
        currentAttachmentPath = nil
        attachmentBar.isHidden = true
        needsLayout = true
    }
    
    public func clearNote() {
        textView.string = ""
        placeholderLabel.isHidden = false
        removeAttachmentClicked()
        flashFeedback("已清空当前记录", isError: false)
    }
    
    public func saveAndNewNote() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentAttachmentPath != nil else {
            flashFeedback("内容为空，无需保存", isError: true)
            return
        }
        
        let att = currentAttachmentPath
        NotchNotesManager.shared.saveToAppleNotes(text: text, attachmentPath: att) { [weak self] success, msg in
            if success {
                self?.textView.string = ""
                self?.placeholderLabel.isHidden = false
                self?.removeAttachmentClicked()
                self?.flashFeedback(msg, isError: false)
            } else {
                self?.flashFeedback(msg, isError: true)
            }
        }
    }
    
    private func flashFeedback(_ msg: String, isError: Bool) {
        statusFeedbackLabel.stringValue = msg
        statusFeedbackLabel.textColor = isError ? NSColor.systemOrange : NSColor.systemGreen
        statusFeedbackLabel.alphaValue = 1.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 2.4
            statusFeedbackLabel.animator().alphaValue = 0.0
        }
    }
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        NotchController.shared.handleMouseMoved(NSEvent.mouseLocation)
        return .copy
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstURL = urls.first {
            attachFile(url: firstURL)
            return true
        }
        return false
    }
    
    private func attachFile(url: URL) {
        currentAttachmentPath = url.path
        attachmentBar.isHidden = false
        attachmentNameLabel.stringValue = url.lastPathComponent
        
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "tiff", "icns"]
        if imageExtensions.contains(ext), let img = NSImage(contentsOfFile: url.path) {
            attachmentIcon.image = img
        } else {
            attachmentIcon.image = NSWorkspace.shared.icon(forFile: url.path)
        }
        
        needsLayout = true
        flashFeedback("已添加附件: \(url.lastPathComponent)", isError: false)
    }
    
    @discardableResult
    public func handlePasteAction() -> Bool {
        let pb = NSPasteboard.general
        
        // 1. 本地文件（Finder 中拷贝的文件或文件夹）
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let localFiles = urls.filter { $0.isFileURL }
            if let firstFile = localFiles.first {
                attachFile(url: firstFile)
                return true
            }
        }
        
        // 2. 纯文本优先：如果包含复制的文字或代码段，直接插入输入框
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.insertText(text, replacementRange: textView.selectedRange())
            placeholderLabel.isHidden = !textView.string.isEmpty
            flashFeedback("已粘贴文字内容", isError: false)
            return true
        }
        
        // 3. 图像数据：如果剪贴板是截图、图片
        if let img = NSImage(pasteboard: pb) {
            let tempDir = NSTemporaryDirectory()
            let filename = "Screenshot_\(Int(Date().timeIntervalSince1970)).png"
            let targetURL = URL(fileURLWithPath: tempDir).appendingPathComponent(filename)
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: targetURL)
                attachFile(url: targetURL)
                flashFeedback("已粘贴图片附件", isError: false)
                return true
            }
        }
        
        return false
    }
    
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && (event.keyCode == 36 || event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\n") {
            saveAndNewNote()
            return true
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v" {
            if handlePasteAction() {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

public class ClosureButton: NSButton {
    private let closure: () -> Void
    public var onHover: ((Bool) -> Void)?
    
    public init(frame frameRect: NSRect, action: @escaping () -> Void) {
        self.closure = action
        super.init(frame: frameRect)
        self.target = self
        self.action = #selector(buttonClicked)
        self.isBordered = false
        self.title = ""
        
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
    
    @objc private func buttonClicked() {
        closure()
    }
}

