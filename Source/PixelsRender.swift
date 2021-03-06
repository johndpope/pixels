//
//  PixelsRender.swift
//  Pixels
//
//  Created by Hexagons on 2018-08-22.
//  Open Source - MIT License
//

import CoreGraphics
import MetalKit

extension Pixels {
    
    public enum MetalErrorCode {
        case IOAF(Int)
        public var info: String {
            switch self {
            case .IOAF(let code):
                return "IOAF code \(code)"
            }
        }
    }
    
    public enum RenderMode {
        case frameLoop
        case direct
    }
    
    func renderPIXs() {
        guard renderMode == .frameLoop else { return }
        loop: for pix in linkedPixs {
            if pix.needsRender {
                if let pixIn = pix as? PIX & PIXInIO {
                    let pixOuts = pixIn.pixInList
                    for (i, pixOut) in pixOuts.enumerated() {
                        if pixOut.texture == nil {
                            log(pix: pix, .warning, .render, "PIX Ins \(i) not rendered.", loop: true)
                            pix.needsRender = false // CHECK
                            continue loop
                        }
                    }
                }
                if pix.view.superview != nil {
                    #if os(iOS)
                    pix.view.metalView.setNeedsDisplay()
                    #elseif os(macOS)
                    guard let size = pix.resolution?.size else {
                        log(pix: pix, .warning, .render, "PIX Resolutuon unknown. Can't render in view.", loop: true)
                        continue
                    }
                    pix.view.metalView.setNeedsDisplay(CGRect(x: 0, y: 0, width: size.width, height: size.height))
                    #endif
                    log(pix: pix, .detail, .render, "View Render requested.", loop: true)
                    guard let currentDrawable: CAMetalDrawable = pix.view.metalView.currentDrawable else {
                        self.log(pix: pix, .error, .render, "Current Drawable not found.")
                        continue
                    }
                    pix.view.metalView.readyToRender = {
                        pix.view.metalView.readyToRender = nil
                        self.renderPIX(pix, with: currentDrawable)
                    }
                } else {
                    renderPIX(pix)
                }
//                if pix.view.superview != nil {
//                    #if os(iOS)
//                    pix.view.metalView.setNeedsDisplay()
//                    #elseif os(macOS)
//                    guard let size = pix.resolution?.size else {
//                        log(pix: pix, .warning, .render, "PIX Resolutuon unknown. Can't render in view.", loop: true)
//                        continue
//                    }
//                    pix.view.metalView.setNeedsDisplay(CGRect(x: 0, y: 0, width: size.width, height: size.height))
//                    #endif
//                    log(pix: pix, .detail, .render, "View Render requested.", loop: true)
//                }
//                if let currentDrawable: CAMetalDrawable = pix.view.metalView.currentDrawable {
//                    if pix.view.superview != nil {
//                        pix.view.metalView.readyToRender = {
//                            pix.view.metalView.readyToRender = nil
//                            self.renderPIX(pix, with: currentDrawable)
//                        }
//                    } else {
//                        renderPIX(pix, with: currentDrawable)
//                    }
//                } else {
//                    log(pix: pix, .error, .render, "Current Drawable not found.")
//                    renderPIX(pix)
//                }
            }
        }
    }
    
    func renderPIX(_ pix: PIX, with currentDrawable: CAMetalDrawable? = nil, force: Bool = false) {
//        let queue = DispatchQueue(label: "pixels-render", qos: .userInteractive, attributes: .concurrent, autoreleaseFrequency: .never, target: nil)
//        queue.async {
        guard !pix.bypass else {
            self.log(pix: pix, .info, .render, "Render bypassed.", loop: true)
            return
        }
            guard !pix.rendering else {
                self.log(pix: pix, .warning, .render, "Render in progress...", loop: true)
                return
            }
//            DispatchQueue.main.async {
                pix.needsRender = false
//            }
            let renderStartTime = Date()
//        let renderStartFrame = frame
            self.log(pix: pix, .detail, .render, "Starting render.\(force ? " Forced." : "")", loop: true)
//        for flowTime in flowTimes {
//            if flowTime.fromPixRenderState.ref.id == pix.id {
//                if !flowTime.fromPixRenderState.requested {
//                    flowTime.fromPixRenderState.requested = true
//                } else {
//
//                }
//            } else {
//
//            }
//        }
            do {
                try self.render(pix, with: currentDrawable, force: force, completed: { texture in
                    let renderTime = -renderStartTime.timeIntervalSinceNow
                    let renderTimeMs = CGFloat(Int(round(renderTime * 10_000))) / 10
//                let renderFrames = self.frame - renderStartFrame
                    self.log(pix: pix, .info, .render, "Rendered \(force ? "Forced. " : "")[\(renderTimeMs)ms]", loop: true)
//                for flowTime in self.flowTimes {
//                    if flowTime.fromPixRenderState.requested {
//                        if !flowTime.fromPixRenderState.rendered {
//                            flowTime.fromPixRenderState.rendered = true
//                        }
//                    }
//                }
//                    DispatchQueue.main.async {
                        pix.didRender(texture: texture, force: force)
//                    }
                }, failed: { error in
                    var ioafMsg: String? = nil
                    let err = error.localizedDescription
                    if err.contains("IOAF code") {
                        if let iofaCode = Int(err[err.count - 2..<err.count - 1]) {
//                            DispatchQueue.main.async {
                                self.metalErrorCodeCallback?(.IOAF(iofaCode))
//                            }
                            ioafMsg = "IOAF code \(iofaCode). Sorry, this is an Metal GPU error, usually seen on older devices."
                        }
                    }
                    self.log(pix: pix, .error, .render, "Render of shader failed... \(force ? "Forced." : "") \(ioafMsg ?? "")", loop: true, e: error)
                })
            } catch {
                self.log(pix: pix, .error, .render, "Render setup failed.\(force ? " Forced." : "")", loop: true, e: error)
            }
//        }
    }
    
    enum RenderError: Error {
        case commandBuffer
        case texture(String)
        case custom(String)
        case drawable(String)
        case commandEncoder
        case uniformsBuffer
        case vertices
        case vertexTexture
    }
    
    func render(_ pix: PIX, with currentDrawable: CAMetalDrawable?, force: Bool, completed: @escaping (MTLTexture) -> (), failed: @escaping (Error) -> ()) throws {
        
//        if #available(iOS 11.0, *) {
//            let sharedCaptureManager = MTLCaptureManager.shared()
//            let myCaptureScope = sharedCaptureManager.makeCaptureScope(device: metalDevice)
//            myCaptureScope.label = "Pixels GPU Capture Scope"
//            sharedCaptureManager.defaultCaptureScope = myCaptureScope
//            myCaptureScope.begin()
//        }

        // Render Time
        let globalRenderTime = Date()
        var localRenderTime = Date()
        var renderTime: Double = -1
        var renderTimeMs: Double = -1
        log(pix: pix, .debug, .metal, "Render Timer: Started")

        
        // MARK: Command Buffer
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RenderError.commandBuffer
        }
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Command Buffer ")
        localRenderTime = Date()
        
        
        // MARK: Input Texture
        
        let generator: Bool = pix is PIXGenerator
        let (inputTexture, secondInputTexture) = try textures(from: pix, with: commandBuffer)
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Input Texture ")
        localRenderTime = Date()
        
        
        // MARK: Drawable
        
        // MARK: Sim...
        var viewDrawable: CAMetalDrawable? = nil
        let drawableTexture: MTLTexture
        if currentDrawable != nil {
            viewDrawable = currentDrawable!
            drawableTexture = currentDrawable!.texture
        } else {
            guard let res = pix.resolution else {
                throw RenderError.drawable("PIX Resolution not set.")
            }
            drawableTexture = try emptyTexture(size: res.size)
        }
        
        if logHighResWarnings {        
            let drawRes = PIX.Res(texture: drawableTexture)
            if (drawRes >= ._16384) != false {
                log(pix: pix, .warning, .render, "Epic res: \(drawRes)")
            } else if (drawRes >= ._8192) != false {
                log(pix: pix, .warning, .render, "Extreme res: \(drawRes)")
            } else if (drawRes >= ._4096) != false {
                log(pix: pix, .warning, .render, "High res: \(drawRes)")
            }
        }
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Drawable ")
        localRenderTime = Date()
        
        
        // MARK: Command Encoder
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawableTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw RenderError.commandEncoder
        }
        commandEncoder.setRenderPipelineState(pix.pipeline)
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Command Encoder ")
        localRenderTime = Date()
        
        
        // MARK: Uniforms
        
        var unifroms: [Float] = pix.uniforms.map { uniform -> Float in return Float(uniform) }
        if let genPix = pix as? PIXGenerator {
            unifroms.append(genPix.premultiply ? 1 : 0)
        }
        if let mergerEffectPix = pix as? PIXMergerEffect {
            unifroms.append(Float(mergerEffectPix.placement.index))
        }
        if pix.shaderNeedsAspect {
            unifroms.append(Float(drawableTexture.width) / Float(drawableTexture.height))
        }
        if !unifroms.isEmpty {
            let size = MemoryLayout<Float>.size * unifroms.count
            guard let uniformsBuffer = metalDevice.makeBuffer(length: size, options: []) else {
                commandEncoder.endEncoding()
                throw RenderError.uniformsBuffer
            }
            let bufferPointer = uniformsBuffer.contents()
            memcpy(bufferPointer, &unifroms, size)
            commandEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        }
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Uniforms ")
        localRenderTime = Date()
        
        
        // MARK: Uniform Arrays
        
        // Hardcoded at 7
        // Defined as ARRMAX in shaders
        let uniformArrayMaxLimit = 7
        
        var uniformArray: [[Float]] = pix.uniformArray.map { uniformValues -> [Float] in
            return uniformValues.map({ uniform -> Float in return Float(uniform) })
        }
        
        if !uniformArray.isEmpty {
            
            var uniformArrayActive: [Bool] = uniformArray.map { _ -> Bool in return true }
            
            if uniformArray.count < uniformArrayMaxLimit {
                let arrayCount = uniformArray.first!.count
                for _ in uniformArray.count..<uniformArrayMaxLimit {
                    var emptyArray: [Float] = []
                    for _ in 0..<arrayCount {
                        emptyArray.append(0.0)
                    }
                    uniformArray.append(emptyArray)
                    uniformArrayActive.append(false)
                }
            } else if uniformArray.count > uniformArrayMaxLimit {
                let origialCount = uniformArray.count
                let overflow = origialCount - uniformArrayMaxLimit
                for _ in 0..<overflow {
                    uniformArray.removeLast()
                    uniformArrayActive.removeLast()
                }
                log(pix: pix, .warning, .render, "Max limit of uniform arrays exceeded. Last values will be truncated. \(origialCount) / \(uniformArrayMaxLimit)")
            }
            
            var uniformFlatMap = uniformArray.flatMap { uniformValues -> [Float] in return uniformValues }
            
            let size: Int = MemoryLayout<Float>.size * uniformFlatMap.count
            guard let uniformsArraysBuffer = metalDevice.makeBuffer(length: size, options: []) else {
                commandEncoder.endEncoding()
                throw RenderError.uniformsBuffer
            }
            let bufferPointer = uniformsArraysBuffer.contents()
            memcpy(bufferPointer, &uniformFlatMap, size)
            commandEncoder.setFragmentBuffer(uniformsArraysBuffer, offset: 0, index: 1)
            
            let activeSize: Int = MemoryLayout<Bool>.size * uniformArrayActive.count
            guard let uniformsArraysActiveBuffer = metalDevice.makeBuffer(length: activeSize, options: []) else {
                commandEncoder.endEncoding()
                throw RenderError.uniformsBuffer
            }
            let activeBufferPointer = uniformsArraysActiveBuffer.contents()
            memcpy(activeBufferPointer, &uniformArrayActive, activeSize)
            commandEncoder.setFragmentBuffer(uniformsArraysActiveBuffer, offset: 0, index: 2)
            
        }
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Uniform Arrays ")
        localRenderTime = Date()
        
        
        // MARK: Fragment Texture
        
        if !generator {
            commandEncoder.setFragmentTexture(inputTexture!, index: 0)
        }
        
        if secondInputTexture != nil {
            commandEncoder.setFragmentTexture(secondInputTexture!, index: 1)
        }
        
        commandEncoder.setFragmentSamplerState(pix.sampler, index: 0)
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Fragment Texture ")
        localRenderTime = Date()
        
        
        // MARK: Vertices
        
        let vertices: Vertices
        if pix.customGeometryActive {
            guard let customVertices = pix.customGeometryDelegate?.customVertices() else {
                commandEncoder.endEncoding()
                throw RenderError.vertices
            }
            vertices = customVertices
        } else {
            vertices = quadVertecis
        }
        
        if vertices.wireframe {
            commandEncoder.setTriangleFillMode(.lines)
        }

        commandEncoder.setVertexBuffer(vertices.buffer, offset: 0, index: 0)
        
        // MARK: Matrix
        
        if !pix.customMatrices.isEmpty {
            var matrices = pix.customMatrices
            guard let uniformBuffer = metalDevice.makeBuffer(length: MemoryLayout<Float>.size * 16 * matrices.count, options: []) else {
                commandEncoder.endEncoding()
                throw RenderError.uniformsBuffer
            }
            let bufferPointer = uniformBuffer.contents()
            memcpy(bufferPointer, &matrices, MemoryLayout<Float>.size * 16 * matrices.count)
            commandEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        }

        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Vertices ")
        localRenderTime = Date()
        
        
        // MARK: Vertex Uniforms
        
        var vertexUnifroms: [Float] = pix.vertexUniforms.map { uniform -> Float in return Float(uniform) }
        if !vertexUnifroms.isEmpty {
            let size = MemoryLayout<Float>.size * vertexUnifroms.count
            guard let uniformsBuffer = metalDevice.makeBuffer(length: size, options: []) else {
                commandEncoder.endEncoding()
                throw RenderError.uniformsBuffer
            }
            let bufferPointer = uniformsBuffer.contents()
            memcpy(bufferPointer, &vertexUnifroms, size)
            commandEncoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
        }
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Vertex Uniforms ")
        localRenderTime = Date()
        
        
        // MARK: Custom Vertex Texture
        
        if pix.customVertexTextureActive {
            
            guard let vtxPixInTexture = pix.customVertexPixIn?.texture else {
                commandEncoder.endEncoding()
                throw RenderError.vertexTexture
            }
            
            commandEncoder.setVertexTexture(vtxPixInTexture, index: 0)
            
            let sampler = try makeSampler(interpolate: .linear, extend: .clampToEdge)
            commandEncoder.setVertexSamplerState(sampler, index: 0)
            
        }
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Custom Vertex Texture ")
        localRenderTime = Date()
        
        
        // MARK: Draw
        
        commandEncoder.drawPrimitives(type: vertices.type, vertexStart: 0, vertexCount: vertices.vertexCount, instanceCount: 1)
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Draw ")
        localRenderTime = Date()
        
        
        // MARK: Encode
        
        commandEncoder.endEncoding()
        
        pix.rendering = true
        
        if viewDrawable != nil {
            commandBuffer.present(viewDrawable!)
        }
        
        // Render Time
        renderTime = -localRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] Encode ")
        localRenderTime = Date()
        
        // Render Time
        renderTime = -globalRenderTime.timeIntervalSinceNow
        renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
        log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] CPU ")
        
        
        // MARK: Render
        
        commandBuffer.addCompletedHandler({ _ in
            pix.rendering = false
            if let error = commandBuffer.error {
                failed(error)
                return
            }
            
            // Render Time
            renderTime = -localRenderTime.timeIntervalSinceNow
            renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
            self.log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] GPU ")
            
            // Render Time
            renderTime = -globalRenderTime.timeIntervalSinceNow
            renderTimeMs = Double(Int(round(renderTime * 1_000_000))) / 1_000
            self.log(pix: pix, .debug, .metal, "Render Timer: [\(renderTimeMs)ms] CPU + GPU ")
            
            self.log(pix: pix, .debug, .metal, "Render Timer: Ended")
            
            DispatchQueue.main.async {
                completed(drawableTexture)
            }
        })
        
        commandBuffer.commit()
        
        
//        if #available(iOS 11.0, *) {
//            let sharedCaptureManager = MTLCaptureManager.shared()
//            guard !sharedCaptureManager.isCapturing else { fatalError() }
//            sharedCaptureManager.defaultCaptureScope?.end()
//        }
        
    }
    
}
