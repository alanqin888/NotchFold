import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // 1. 初始化刘海灵动岛中心
        NotchController.shared.setup()
        
        // 2. 实时绑定 Apple Silicon 物理开合角度传感器 (las)
        LidMonitor.shared.onAngleChanged = { angle in
            FoldWindowController.shared.updateLidAngle(angle)
            NotchController.shared.updateAngleDisplay(angle)
        }
        
        // 3. 注册 ⌘⇧F 演示快捷键与 Esc 退出快捷键
        setupKeyboardMonitors()
        
        print("✅ NotchFold 已就绪：Metal GPU 5大光学折叠管线激活，实时硬件传感器联动中。")
    }
    
    private func setupKeyboardMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.handleKeyEvent(event) {
                return nil
            }
            return event
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = self.handleKeyEvent(event)
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Esc: 退出展开的刘海面板或折叠覆盖层
        if event.keyCode == 53 {
            if NotchController.shared.isExpanded {
                DispatchQueue.main.async {
                    NotchController.shared.collapse()
                }
                return true
            }
            if FoldWindowController.shared.isCurrentlyVisible {
                DispatchQueue.main.async {
                    FoldWindowController.shared.dismissFold()
                }
                return true
            }
        }
        
        // ⌘⇧F: 手动触发 5 秒完整光学折叠流体演示
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCmdShift = flags.contains(.command) && flags.contains(.shift)
        if isCmdShift && event.charactersIgnoringModifiers?.lowercased() == "f" {
            DispatchQueue.main.async {
                FoldWindowController.shared.manualDemoSequence()
            }
            return true
        }
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
