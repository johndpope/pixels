//
//  PIX.swift
//  Pixels
//
//  Created by Hexagons on 2018-07-20.
//  Open Source - MIT License
//

import Metal
import MetalKit
import MetalPerformanceShaders

open class PIX {
    
    public var id = UUID()
    public var name: String?
    
    public weak var delegate: PIXDelegate?
    
    let pixels = Pixels.main
    
    open var shader: String { return "" }
    
    var liveValues: [LiveValue] { return [] }
    var preUniforms: [CGFloat] { return [] }
    var postUniforms: [CGFloat] { return [] }
    open var uniforms: [CGFloat] {
        var vals: [CGFloat] = []
        vals.append(contentsOf: preUniforms)
        for liveValue in liveValues {
            if let liveFloat = liveValue as? LiveFloat {
                vals.append(liveFloat.uniform)
            } else if let liveInt = liveValue as? LiveInt {
                vals.append(CGFloat(liveInt.uniform))
            } else if let liveBool = liveValue as? LiveBool {
                vals.append(liveBool.uniform ? 1.0 : 0.0)
            } else if let liveColor = liveValue as? LiveColor {
                vals.append(contentsOf: liveColor.uniformList)
            } else if let livePoint = liveValue as? LivePoint {
                vals.append(contentsOf: livePoint.uniformList)
            } else if let liveSize = liveValue as? LiveSize {
                vals.append(contentsOf: liveSize.uniformList)
            }
        }
        vals.append(contentsOf: postUniforms)
        return vals
    }
    
    var liveArray: [[LiveFloat]] { return [] }
    open var uniformArray: [[CGFloat]] {
        return liveArray.map({ liveFloats -> [CGFloat] in
            return liveFloats.map({ liveFloat -> CGFloat in
                return liveFloat.uniform
            })
        })
    }

    open var vertexUniforms: [CGFloat] { return [] }
    var shaderNeedsAspect: Bool { return false }
    
    public var bypass: Bool = false {
        didSet {
            guard !bypass else { return }
            setNeedsRender()
        }
    }

    var _texture: MTLTexture?
    var texture: MTLTexture? {
        get {
            guard !bypass else {
                guard let inPix = self as? PIXInIO else { return nil }
                return inPix.pixInList.first?.texture
            }
            return _texture
        }
        set {
            _texture = newValue
        }
    }
    public var didRenderTexture: Bool {
        return _texture != nil
    }
    
    public let view: PIXView
    
    public var interpolate: InterpolateMode = .linear { didSet { updateSampler() } }
    public var extend: ExtendMode = .zero { didSet { updateSampler() } }
    var compare: MTLCompareFunction = .never
    
    var pipeline: MTLRenderPipelineState!
    var sampler: MTLSamplerState!
    var allGood: Bool {
        return pipeline != nil && sampler != nil
    }
    
    public var customRenderActive: Bool = false
    public var customRenderDelegate: PixelsCustomRenderDelegate?
    public var customMergerRenderActive: Bool = false
    public var customMergerRenderDelegate: PixelsCustomMergerRenderDelegate?
    public var customGeometryActive: Bool = false
    public var customGeometryDelegate: PixelsCustomGeometryDelegate?
    open var customMetalLibrary: MTLLibrary? { return nil }
    open var customVertexShaderName: String? { return nil }
    open var customVertexTextureActive: Bool { return false }
    open var customVertexPixIn: (PIX & PIXOut)? { return nil }
    open var customMatrices: [matrix_float4x4] { return [] }
    public var customLinkedPixs: [PIX] = []

    var rendering = false
    var needsRender = false {
        didSet {
            guard needsRender else { return }
            guard pixels.renderMode == .direct else { return }
            pixels.renderPIX(self)
        }
    }
    
    // MARK: - Life Cycle
    
    init() {
    
        view = PIXView()
        
        guard shader != "" else {
            pixels.log(pix: self, .fatal, nil, "Shader not defined.")
            return
        }
        do {
            let frag = try pixels.makeFrag(shader, with: customMetalLibrary, from: self)
            let vtx: MTLFunction? = customVertexShaderName != nil ? try pixels.makeVertexShader(customVertexShaderName!, with: customMetalLibrary) : nil
            pipeline = try pixels.makeShaderPipeline(frag, with: vtx)
            sampler = try pixels.makeSampler(interpolate: interpolate.mtl, extend: extend.mtl)
        } catch {
            pixels.log(pix: self, .fatal, nil, "Initialization failed.", e: error)
        }
            
        pixels.add(pix: self)
        
        pixels.log(pix: self, .detail, nil, "Linked with Pixels.", clean: true)
    
    }
    
    // MARK: Sampler
    
    func updateSampler() {
        do {
            sampler = try pixels.makeSampler(interpolate: interpolate.mtl, extend: extend.mtl)
            pixels.log(pix: self, .info, nil, "New Sample Mode. Interpolate: \(interpolate) & Extend: \(extend)")
            setNeedsRender()
        } catch {
            pixels.log(pix: self, .error, nil, "Error setting new Sample Mode. Interpolate: \(interpolate) & Extend: \(extend)", e: error)
        }
    }
    
    // MARK: - Render
    
    public func setNeedsRender() {
        guard !bypass else {
            renderOuts()
            return
        }
        guard !needsRender else {
//            pixels.log(pix: self, .warning, .render, "Already requested.", loop: true)
            return
        }
        guard resolution != nil else {
//            pixels.log(pix: self, .warning, .render, "Resolution unknown.", loop: true)
            return
        }
        guard view.metalView.res != nil else {
            pixels.log(pix: self, .warning, .render, "Metal View res not set.", loop: true)
            pixels.log(pix: self, .debug, .render, "Auto applying Res...", loop: true)
            applyRes {
                self.setNeedsRender()
            }
            return
        }
        if let pixResource = self as? PIXResource {
            guard pixResource.pixelBuffer != nil else {
                pixels.log(pix: self, .warning, .render, "Content not loaded.", loop: true)
                return
            }
        }
        pixels.log(pix: self, .detail, .render, "Requested.", loop: true)
//        delegate?.pixWillRender(self)
        needsRender = true
    }
    
    open func didRender(texture: MTLTexture, force: Bool = false) {
        self.texture = texture
        delegate?.pixDidRender(self)
        for customLinkedPix in customLinkedPixs {
            customLinkedPix.setNeedsRender()
        }
        if !force { // CHECK the force!
            renderOuts()
        }
    }
    
    func renderOuts() {
        if let pixOut = self as? PIXOutIO {
            for pixOutPath in pixOut.pixOutPathList {
                let pix = pixOutPath.pixIn
                guard !pix.destroyed else { continue }
                pix.setNeedsRender()
            }
        }
    }
    
    // MARK: - Connect
    
    struct OutPath {
        let pixIn: PIX & PIXIn
        let inIndex: Int
    }
    
    func setNeedsConnect() {
        if self is PIXIn {
            if var pixInSingle = self as? PIXInSingle {
                if pixInSingle.inPix != nil {
                    connectSingle(pixInSingle.inPix! as! PIX & PIXOutIO)
                } else {
                    disconnectSingle()
                }
            } else if let pixInMerger = self as? PIXInMerger {
                if pixInMerger.inPixA != nil && pixInMerger.inPixB != nil {
                    connectMerger(pixInMerger.inPixA! as! PIX & PIXOutIO, pixInMerger.inPixB! as! PIX & PIXOutIO)
                } else {
                    // CHECK DISCONNECT
                }
            } else if let pixInMulti = self as? PIXInMulti {
                connectMulti(pixInMulti.inPixs as! [PIX & PIXOutIO])
            }
        }
    }
    
    func connectSingle(_ pixOut: PIX & PIXOutIO) {
        guard pixOut != self else {
            pixels.log(.error, .connection, "Can't connect to self.")
            return
        }
        var pixOut = pixOut
        guard var pixInIO = self as? PIX & PIXInIO else { pixels.log(pix: self, .error, .connection, "PIXIn's Only"); return }
        pixInIO.pixInList = [pixOut]
        pixOut.pixOutPathList.append(OutPath(pixIn: pixInIO, inIndex: 0))
        pixels.log(pix: self, .info, .connection, "Connected Single: \(pixOut)")
        applyRes { self.setNeedsRender() }
    }
    
    func connectMerger(_ pixOutA: PIX & PIXOutIO, _ pixOutB: PIX & PIXOutIO) {
        var pixOutA = pixOutA
        var pixOutB = pixOutB
        guard var pixInIO = self as? PIX & PIXInIO else { pixels.log(pix: self, .error, .connection, "PIXIn's Only"); return }
        pixInIO.pixInList = [pixOutA, pixOutB]
        pixOutA.pixOutPathList.append(OutPath(pixIn: pixInIO, inIndex: 0))
        pixOutB.pixOutPathList.append(OutPath(pixIn: pixInIO, inIndex: 1))
        pixels.log(pix: self, .info, .connection, "Connected Merger: \(pixOutA), \(pixOutB)")
        applyRes { self.setNeedsRender() }
    }
    
    func connectMulti(_ pixOuts: [PIX & PIXOutIO]) {
        guard var pixInIO = self as? PIX & PIXInIO else { pixels.log(pix: self, .error, .connection, "PIXIn's Only"); return }
        pixInIO.pixInList = pixOuts
        for (i, pixOut) in pixOuts.enumerated() {
            var pixOut = pixOut
            pixOut.pixOutPathList.append(OutPath(pixIn: pixInIO, inIndex: i)) // CHECK override
        }
        pixels.log(pix: self, .info, .connection, "Connected Multi: \(pixOuts)")
        applyRes { self.setNeedsRender() }
    }
    
    // MARK: Diconnect
    
    func disconnectSingle() {
        guard var pixInIO = self as? PIX & PIXInIO else { pixels.log(pix: self, .error, .connection, "PIXIn's Only"); return }
        guard var pixOut = pixInIO.pixInList.first as? PIXOutIO else { return }
        for (i, pixOutPath) in pixOut.pixOutPathList.enumerated() {
            if pixOutPath.pixIn == pixInIO {
                pixOut.pixOutPathList.remove(at: i)
                break
            }
        }
        pixInIO.pixInList = []
        pixels.log(pix: self, .info, .connection, "Disonnected Single.")
//        applyRes { self.setNeedsRender() }
//        view.setResolution(nil)
    }
    
    // MARK: - Other
    
    // MARL: Custom Linking
    
    public func customLink(to pix: PIX) {
        for customLinkedPix in customLinkedPixs {
            if customLinkedPix == pix {
                return
            }
        }
        customLinkedPixs.append(pix)
    }
    
    public func customDelink(from pix: PIX) {
        for (i, customLinkedPix) in customLinkedPixs.enumerated() {
            if customLinkedPix == pix {
                customLinkedPixs.remove(at: i)
                return
            }
        }
    }
    
    // MARK: Operator Overloading
    
    public static func ==(lhs: PIX, rhs: PIX) -> Bool {
        return lhs.id == rhs.id
    }
    
    public static func !=(lhs: PIX, rhs: PIX) -> Bool {
        return lhs.id != rhs.id
    }
    
    // MARK: Live
    
    func checkLive() {
        for liveValue in liveValues {
            if liveValue.uniformIsNew {
                setNeedsRender()
                break
            }
        }
        for liveValues in liveArray {
            for liveValue in liveValues {
                if liveValue.uniformIsNew {
                    setNeedsRender()
                    break
                }
            }
        }
    }
    
    // MARK: Clean
    
    var destroyed = false
    public func destroy() {
        pixels.remove(pix: self)
        texture = nil
        destroyed = true
    }
    
    deinit {
        // CHECK retain count...
        pixels.remove(pix: self)
        // Disconnect...
    }
    
}
