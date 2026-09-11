import AppKit
import ScreenCaptureKit
import CoreMedia
import OSLog

public final class DesktopCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    public let frames = FrameStore()
    private let logger = Logger(subsystem: "com.notchfold.app", category: "capture")
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.notchfold.frames", qos: .userInteractive)
    private var generation = 0
    private var starting = false
    private var ownApplication: SCRunningApplication?
    
    public var onFailure: ((String) -> Void)?
    public var onUnavailable: (() -> Void)?
    public var onFirstFrame: (() -> Void)?
    public private(set) var hasFrame = false
    public var isRunning: Bool { stream != nil || starting }
    
    @MainActor private func availableContent() async throws -> SCShareableContent {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        if let own = content.applications.first(where: { $0.processID == getpid() }) {
            ownApplication = own
        }
        return content
    }
    
    @MainActor public func verifyAccess() async throws {
        let content = try await availableContent()
        guard !content.displays.isEmpty else {
            throw NSError(domain: "DesktopCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "无可用屏幕"])
        }
    }
    
    @MainActor public func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int = 60) async throws {
        guard !isRunning else { return }
        // 关键防护：静默只读预检。如果用户未主动在系统偏好中授权，绝不调用 ScreenCaptureKit，避免触发烦人的系统权限弹窗！
        guard CGPreflightScreenCaptureAccess() else { return }
        generation += 1
        let token = generation
        starting = true
        defer { if token == generation { starting = false } }
        
        let available: SCShareableContent
        do {
            available = try await availableContent()
        } catch {
            guard token == generation else { return }
            throw error
        }
        guard token == generation else { return }
        guard let display = available.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "DesktopCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到内置显示屏"])
        }
        
        // 关键：排除自己，避免折叠遮罩出现无限递归镜像
        let excludingApps = ownApplication != nil ? [ownApplication!] : []
        let filter = SCContentFilter(display: display, excludingApplications: excludingApps, exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.colorSpaceName = CGColorSpace.sRGB
        config.scalesToFit = true
        
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        stream = newStream
        
        do {
            try await newStream.startCapture()
            if token != generation { try? await newStream.stopCapture() }
        } catch {
            guard token == generation else { return }
            stream = nil
            frames.clear()
            throw error
        }
    }
    
    @MainActor public func stop() {
        generation += 1
        starting = false
        let previous = stream
        stream = nil
        frames.clear()
        hasFrame = false
        if let previous {
            Task { try? await previous.stopCapture() }
        }
    }
    
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        guard let rawStatus = attachments?.first?[.status] as? Int, let status = SCFrameStatus(rawValue: rawStatus) else { return }
        let buffer = sampleBuffer.imageBuffer
        
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            if status == .complete, let buffer {
                self.frames.put(buffer)
                if !self.hasFrame {
                    self.hasFrame = true
                    self.onFirstFrame?()
                }
            } else if status == .blank || status == .suspended || status == .stopped {
                self.frames.clear()
                self.hasFrame = false
                self.onUnavailable?()
            }
        }
    }
    
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.frames.clear()
            self.hasFrame = false
            self.onFailure?(error.localizedDescription)
        }
    }
}
