import AppKit
import MetalKit
import CoreVideo

public final class FoldRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    public let pipeline: MTLRenderPipelineState
    private let downsamplePipeline: MTLComputePipelineState
    
    private var blurPyramid: MTLTexture?
    private var blurLevels: [MTLTexture] = []
    private var blurredRevision: UInt64?
    private var renderedRevision: UInt64?
    private var renderedUniforms: FoldUniforms?
    private var cache: CVMetalTextureCache?
    private let inFlight = DispatchSemaphore(value: 3)
    
    public var frames: FrameStore?
    public var fallback: MTLTexture?
    public var parameters: () -> FoldUniforms = { FoldUniforms() }
    public var animatedProgress: (() -> Double?)?
    public var pausesWhenSettled = false
    public var keepsAnimating: () -> Bool = { false }
    public var onFailure: ((String) -> Void)?
    public var onPresented: (() -> Void)?
    
    public private(set) var progress: Double = 0
    private var lastTime = ProcessInfo.processInfo.systemUptime
    public private(set) var drawnFrames = 0
    
    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "FoldRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal 命令队列创建失败"])
        }
        self.queue = queue
        
        let library = try device.makeLibrary(source: FoldShader.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        
        guard let downsample = library.makeFunction(name: "foldDownsample") else {
            throw NSError(domain: "FoldRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "下采样计算着色器不可用"])
        }
        self.downsamplePipeline = try device.makeComputePipelineState(function: downsample)
        
        super.init()
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw NSError(domain: "FoldRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Metal 纹理缓存初始化失败"])
        }
        
        // 创建默认高质量壁纸作为降级底图
        self.fallback = loadWallpaperTexture()
    }
    
    public func configure(_ view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.delegate = self
        view.isPaused = false
        view.enableSetNeedsDisplay = true
    }
    
    public func resetProgress(to value: Double) {
        progress = value
        lastTime = ProcessInfo.processInfo.systemUptime
        renderedUniforms = nil
    }
    
    public func wake(_ view: MTKView) {
        if view.isPaused { lastTime = ProcessInfo.processInfo.systemUptime }
        view.isPaused = false
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderedUniforms = nil
    }
    
    public func draw(in view: MTKView) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard view.window?.isVisible == true, inFlight.wait(timeout: .now()) == .success else { return }
        var committed = false
        defer { if !committed { inFlight.signal() } }
        
        var cvTexture: CVMetalTexture?
        let frame = frames?.get()
        let pixelBuffer = frame?.0
        let revision = pixelBuffer == nil ? 0 : frame!.2
        var texture = fallback
        
        if let pixelBuffer, let cache {
            let result = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm,
                CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &cvTexture
            )
            if result == kCVReturnSuccess, let cvTexture {
                texture = CVMetalTextureGetTexture(cvTexture)
            }
        }
        
        guard let texture else { return }
        let now = ProcessInfo.processInfo.systemUptime
        var uniforms = parameters()
        let target = Double(uniforms.progress)
        
        progress = animatedProgress?() ?? FoldMath.smooth(current: progress, target: Double(uniforms.progress), dt: min(0.1, now - lastTime))
        lastTime = now
        uniforms.progress = Float(progress)
        uniforms.size = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        
        let settled = abs(progress - target) < 0.0001 && !keepsAnimating()
        if renderedRevision == revision && renderedUniforms == uniforms {
            if pausesWhenSettled && settled { view.isPaused = true }
            return
        }
        
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { return }
        
        do {
            try encode(command: command, pass: pass, texture: texture, uniforms: uniforms, sourceRevision: revision)
        } catch {
            blurredRevision = nil
            renderedUniforms = nil
            onFailure?(error.localizedDescription)
            return
        }
        
        let retainedTexture = cvTexture
        command.addCompletedHandler { [weak self, inFlight, pixelBuffer, retainedTexture] buffer in
            withExtendedLifetime((pixelBuffer, retainedTexture)) {}
            inFlight.signal()
            DispatchQueue.main.async {
                guard let self else { return }
                if buffer.status == .completed {
                    self.onPresented?()
                } else if buffer.status == .error {
                    self.onFailure?(buffer.error?.localizedDescription ?? "Metal 绘制出错")
                }
            }
        }
        
        command.present(drawable)
        committed = true
        command.commit()
        drawnFrames += 1
        renderedRevision = revision
        renderedUniforms = uniforms
        if pausesWhenSettled && settled { view.isPaused = true }
    }
    
    private func prepareBlur(command: MTLCommandBuffer, input: MTLTexture, revision: UInt64?) throws -> MTLTexture {
        if blurPyramid?.width != input.width || blurPyramid?.height != input.height || blurPyramid?.pixelFormat != input.pixelFormat {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: input.pixelFormat,
                width: input.width,
                height: input.height,
                mipmapped: true
            )
            descriptor.mipmapLevelCount = min(9, descriptor.mipmapLevelCount)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .shaderWrite, .pixelFormatView]
            
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw NSError(domain: "FoldRenderer", code: 4, userInfo: [NSLocalizedDescriptionKey: "模糊金字塔显存分配失败"])
            }
            var levels: [MTLTexture] = []
            for level in 0..<texture.mipmapLevelCount {
                guard let view = texture.makeTextureView(
                    pixelFormat: texture.pixelFormat,
                    textureType: .type2D,
                    levels: level..<(level + 1),
                    slices: 0..<1
                ) else {
                    throw NSError(domain: "FoldRenderer", code: 5, userInfo: [NSLocalizedDescriptionKey: "模糊分级视图创建失败"])
                }
                levels.append(view)
            }
            blurPyramid = texture
            blurLevels = levels
            blurredRevision = nil
        }
        
        if let revision, blurredRevision == revision, let pyramid = blurPyramid {
            return pyramid
        }
        
        guard let pyramid = blurPyramid, let blit = command.makeBlitCommandEncoder() else {
            throw NSError(domain: "FoldRenderer", code: 6, userInfo: [NSLocalizedDescriptionKey: "Blit 编码器不可用"])
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
            sourceSize: MTLSize(width: input.width, height: input.height, depth: 1),
            to: pyramid, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin()
        )
        blit.endEncoding()
        
        for level in 1..<blurLevels.count {
            guard let encoder = command.makeComputeCommandEncoder() else {
                throw NSError(domain: "FoldRenderer", code: 7, userInfo: [NSLocalizedDescriptionKey: "计算编码器不可用"])
            }
            encoder.setComputePipelineState(downsamplePipeline)
            encoder.setTexture(blurLevels[level - 1], index: 0)
            encoder.setTexture(blurLevels[level], index: 1)
            encoder.dispatchThreads(
                MTLSize(width: blurLevels[level].width, height: blurLevels[level].height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
            )
            encoder.endEncoding()
        }
        blurredRevision = revision
        return pyramid
    }
    
    public func encode(command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, texture: MTLTexture, uniforms: FoldUniforms, sourceRevision: UInt64? = nil) throws {
        let moving = uniforms.progress > 0.00001 && uniforms.progress < 1.0 && uniforms.fadeOnly < 0.5
        let needsBlur = moving && (uniforms.blur > 0 || uniforms.selectedEffect.needsPrefilteredSource)
        let blurred = needsBlur ? try prepareBlur(command: command, input: texture, revision: sourceRevision) : texture
        
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw NSError(domain: "FoldRenderer", code: 8, userInfo: [NSLocalizedDescriptionKey: "渲染编码器不可用"])
        }
        var uniforms = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(blurred, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
    
    public func loadWallpaperTexture() -> MTLTexture? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let img = NSImage(contentsOf: url),
              let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(cgImage: cgImg, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
    }
}
