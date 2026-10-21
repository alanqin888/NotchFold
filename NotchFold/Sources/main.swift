import Cocoa

// ─── 单实例检查：防止重复启动多个进程 ───
let myPID = ProcessInfo.processInfo.processIdentifier
let bundleID = "com.alan.NotchFold"
let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
for otherApp in runningApps {
    if otherApp.processIdentifier != myPID {
        print("⚠️ 检测到已有 NotchFold 实例 (PID: \(otherApp.processIdentifier)) 正在运行，激活已有实例并退出当前进程。")
        otherApp.activate()
        exit(0)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // 0. 初始化系统标准主菜单（提供 ⌘C/⌘V/⌘A/⌘Z 剪切板支持与 ⌘Q 退出）
        setupMainMenu()
        
        // 1. 初始化刘海灵动岛中心
        NotchController.shared.setup()
        
        // 2. 实时绑定 Apple Silicon 物理开合角度传感器 (las)
        LidMonitor.shared.onAngleChanged = { angle in
            FoldWindowController.shared.updateLidAngle(angle)
            NotchController.shared.updateAngleDisplay(angle)
        }
        
        // 3. 注册快捷键监听
        setupKeyboardMonitors()
        
        print("✅ NotchFold 已就绪：Metal GPU 5大光学折叠管线激活，实时硬件传感器联动中。")
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // 应用主菜单 (Application Menu)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 NotchFold", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 NotchFold", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 NotchFold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // 编辑菜单 (Edit Menu - 解决 Accessory 应用下 NSTextView 无法 ⌘V/⌘C/⌘A/⌘Z 的系统限制)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        NSApp.mainMenu = mainMenu
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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        
        // ⌘Q: 退出整个应用程序
        if flags == .command && key == "q" {
            if NotchController.shared.isExpanded || FoldWindowController.shared.isCurrentlyVisible {
                NSApp.terminate(nil)
                return true
            }
        }
        
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
        let isCmdShift = flags.contains(.command) && flags.contains(.shift)
        if isCmdShift && key == "f" {
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
