import Cocoa

public final class NotchNotesManager {
    public static let shared = NotchNotesManager()
    
    private let backupFolder: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.backupFolder = appSupport.appendingPathComponent("NotchFold/notes_backup", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
    }
    
    /// 将文本与附件（图片/文件）保存到系统备忘录 (Apple Notes)
    public func saveToAppleNotes(text: String, attachmentPath: String?, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty || attachmentPath != nil else {
                DispatchQueue.main.async { completion(false, "内容为空，未保存") }
                return
            }
            
            // 本地归档备份一份
            self?.saveLocalBackup(text: trimmedText, attachmentPath: attachmentPath)
            
            // 构建 HTML 内容
            let bodyHTML = trimmedText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br/>")
            
            let escapedHTML = bodyHTML
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            
            var script = "tell application \"Notes\"\n"
            if let path = attachmentPath, FileManager.default.fileExists(atPath: path) {
                let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
                script += "    set theNote to make new note with properties {body:\"<div><p>\(escapedHTML)</p></div>\"}\n"
                script += "    make new attachment at theNote with data (POSIX file \"\(escapedPath)\")\n"
            } else {
                script += "    make new note with properties {body:\"<div><p>\(escapedHTML)</p></div>\"}\n"
            }
            script += "end tell\n"
            
            let process = Process()
            process.launchPath = "/usr/bin/osascript"
            process.arguments = ["-e", script]
            
            do {
                try process.run()
                process.waitUntilExit()
                let success = (process.terminationStatus == 0)
                DispatchQueue.main.async {
                    if success {
                        completion(true, "✓ 已存入系统备忘录并开启新笔记")
                    } else {
                        completion(false, "系统备忘录保存失败，已在本地暂存")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "执行出错: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func saveLocalBackup(text: String, attachmentPath: String?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let fileURL = backupFolder.appendingPathComponent("Note_\(timestamp).txt")
        var content = "时间: \(Date())\n\n" + text
        if let att = attachmentPath {
            content += "\n\n附件: \(att)"
        }
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
