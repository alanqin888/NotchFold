import Cocoa

public struct CustomShortcut: Codable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var subtitle: String?
    public var fallbackURL: String?
    public var isApp: Bool
    
    public init(id: String = UUID().uuidString, name: String, path: String, subtitle: String? = nil, fallbackURL: String? = nil, isApp: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.subtitle = subtitle
        self.fallbackURL = fallbackURL
        self.isApp = isApp
    }
    
    public var displaySubtitle: String {
        if let sub = subtitle, !sub.isEmpty { return sub }
        if name.localizedCaseInsensitiveContains("gpt") || name.localizedCaseInsensitiveContains("gemini") || name.localizedCaseInsensitiveContains("claude") {
            return "AI 智能体"
        }
        if name.localizedCaseInsensitiveContains("chrome") || name.localizedCaseInsensitiveContains("safari") || name.localizedCaseInsensitiveContains("edge") {
            return "网络浏览器"
        }
        if name.localizedCaseInsensitiveContains("code") || name.localizedCaseInsensitiveContains("xcode") {
            return "开发工具"
        }
        if name.localizedCaseInsensitiveContains("微信") || name.localizedCaseInsensitiveContains("wechat") || name.localizedCaseInsensitiveContains("飞书") || name.localizedCaseInsensitiveContains("钉钉") {
            return "即时通讯"
        }
        if name.localizedCaseInsensitiveContains("终端") || name.localizedCaseInsensitiveContains("iterm") {
            return "系统终端"
        }
        if name.localizedCaseInsensitiveContains("访达") || name.localizedCaseInsensitiveContains("finder") {
            return "文件浏览"
        }
        return isApp ? "快捷应用" : "常用目录"
    }
}

public final class AppConfig {
    public static let shared = AppConfig()
    
    public var autoFoldOnLidAngle: Bool = true
    
    // 安全开合阈值：正常使用开盖角为 100°~120°，必须在合向键盘过 80° 时才进入折叠，严禁在正常开盖时误触发！
    public var clearAngle: Double = 80.0
    public var fullFoldAngle: Double = 10.0
    public var soundEnabled: Bool = true
    
    // 折叠渲染参数
    public var selectedEffect: FoldEffect = .flex {
        didSet { UserDefaults.standard.set(selectedEffect.rawValue, forKey: "selectedEffect") }
    }
    public var perspective: Double = 0.7
    public var blur: Double = 0.65
    public var shadow: Double = 0.65
    public var clearWhenStill: Bool = true // 静止两秒平滑恢复清晰
    
    public var shortcuts: [CustomShortcut] = []
    
    private let configURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("NotchFold", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.configURL = folder.appendingPathComponent("shortcuts.json")
        
        if let savedEffect = UserDefaults.standard.string(forKey: "selectedEffect"),
           let eff = FoldEffect(rawValue: savedEffect) {
            self.selectedEffect = eff
        }
        
        loadShortcuts()
    }
    
    public func loadShortcuts() {
        if let data = try? Data(contentsOf: configURL),
           let list = try? JSONDecoder().decode([CustomShortcut].self, from: data),
           !list.isEmpty {
            self.shortcuts = list
        } else {
            var defaults: [CustomShortcut] = []
            
            // 1. AI 智能体
            if FileManager.default.fileExists(atPath: "/Applications/ChatGPT.app") {
                defaults.append(CustomShortcut(name: "ChatGPT", path: "/Applications/ChatGPT.app", subtitle: "AI 智能体", isApp: true))
            } else {
                defaults.append(CustomShortcut(name: "ChatGPT", path: "/System/Library/CoreServices/Finder.app", subtitle: "AI 智能体", fallbackURL: "https://chatgpt.com", isApp: true))
            }
            
            if FileManager.default.fileExists(atPath: "/Applications/Gemini.app") {
                defaults.append(CustomShortcut(name: "Gemini", path: "/Applications/Gemini.app", subtitle: "AI 智能体", isApp: true))
            } else {
                defaults.append(CustomShortcut(name: "Gemini", path: "/System/Library/CoreServices/Finder.app", subtitle: "AI 智能体", fallbackURL: "https://gemini.google.com", isApp: true))
            }
            
            // 2. 常用应用
            if FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app") {
                defaults.append(CustomShortcut(name: "Chrome", path: "/Applications/Google Chrome.app", subtitle: "网络浏览器", isApp: true))
            }
            defaults.append(CustomShortcut(name: "Safari", path: "/Applications/Safari.app", subtitle: "原生浏览器", isApp: true))
            
            if FileManager.default.fileExists(atPath: "/Applications/Visual Studio Code.app") {
                defaults.append(CustomShortcut(name: "VS Code", path: "/Applications/Visual Studio Code.app", subtitle: "代码开发", isApp: true))
            }
            if FileManager.default.fileExists(atPath: "/Applications/WeChat.app") {
                defaults.append(CustomShortcut(name: "微信", path: "/Applications/WeChat.app", subtitle: "即时通讯", isApp: true))
            }
            defaults.append(CustomShortcut(name: "终端", path: "/System/Applications/Utilities/Terminal.app", subtitle: "系统命令行", isApp: true))
            defaults.append(CustomShortcut(name: "访达", path: "/System/Library/CoreServices/Finder.app", subtitle: "文件系统", isApp: true))
            
            // 3. 常用目录
            defaults.append(CustomShortcut(name: "下载", path: NSString(string: "~/Downloads").expandingTildeInPath, subtitle: "本地下载", isApp: false))
            defaults.append(CustomShortcut(name: "代码", path: NSString(string: "~/Code").expandingTildeInPath, subtitle: "工程源码", isApp: false))
            defaults.append(CustomShortcut(name: "桌面", path: NSString(string: "~/Desktop").expandingTildeInPath, subtitle: "桌面文件", isApp: false))
            
            self.shortcuts = defaults
            saveShortcuts()
        }
    }
    
    public func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            try? data.write(to: configURL)
        }
    }
    
    public func addShortcut(name: String, path: String, subtitle: String? = nil, isApp: Bool) {
        let item = CustomShortcut(name: name, path: path, subtitle: subtitle, isApp: isApp)
        shortcuts.append(item)
        saveShortcuts()
    }
    
    @discardableResult
    public func addFromDroppedURL(_ url: URL) -> CustomShortcut? {
        let path = url.path
        if let existing = shortcuts.first(where: { $0.path == path }) {
            return existing
        }
        
        let isApp = path.hasSuffix(".app") || (try? url.resourceValues(forKeys: [.isApplicationKey]))?.isApplication == true
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        
        let rawName = url.deletingPathExtension().lastPathComponent
        let displayName = FileManager.default.displayName(atPath: path)
        let name = displayName.isEmpty ? rawName : displayName
        
        let subtitle: String
        if isApp {
            let lower = name.lowercased()
            if lower.contains("chatgpt") || lower.contains("gemini") || lower.contains("claude") || lower.contains("copilot") || lower.contains("ai") || lower.contains("ollama") {
                subtitle = "AI 智能体"
            } else {
                subtitle = "常用应用"
            }
        } else if isDir {
            subtitle = "本地文件夹"
        } else {
            subtitle = "快捷文件"
        }
        
        let item = CustomShortcut(name: name, path: path, subtitle: subtitle, isApp: isApp)
        shortcuts.append(item)
        saveShortcuts()
        return item
    }
    
    public func removeShortcut(id: String) {
        shortcuts.removeAll { $0.id == id }
        saveShortcuts()
    }
    
    public static func openItem(_ item: CustomShortcut) {
        if let fallback = item.fallbackURL, !FileManager.default.fileExists(atPath: item.path) {
            if let url = URL(string: fallback) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        
        let url = URL(fileURLWithPath: item.path)
        if item.isApp {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    
    public static func triggerScreenshot(mode: ScreenshotMode) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/usr/sbin/screencapture"
            switch mode {
            case .interactive:
                let desktop = NSString(string: "~/Desktop").expandingTildeInPath
                let filename = "Screenshot_\(Int(Date().timeIntervalSince1970)).png"
                let target = (desktop as NSString).appendingPathComponent(filename)
                task.arguments = ["-i", target]
            case .toClipboard:
                task.arguments = ["-i", "-c"]
            case .window:
                task.arguments = ["-i", "-w", "-c"]
            }
            try? task.run()
        }
    }
}

public enum ScreenshotMode {
    case interactive
    case toClipboard
    case window
}
