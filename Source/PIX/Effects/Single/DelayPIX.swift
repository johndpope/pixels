//
//  DelayPIX.swift
//  Pixels
//
//  Created by Anton Heestand on 2018-09-23.
//  Open Source - MIT License
//

import Metal

public class DelayPIX: PIXSingleEffect, PixelsCustomRenderDelegate {
    
    override open var shader: String { return "nilPIX" }
    
    // MARK: - Private Properties
    
    var cachedTextures: [MTLTexture] = []
    
    // MARK: - Public Properties
    
//    public var seconds: LiveFloat = 1.0
    public var delayFrames: Int = 10 { didSet { setNeedsRender() } }
    
    // MARK: - Property Helpers
    
//    override var liveValues: [LiveValue] {
//        return [seconds]
//    }
    
    // MARK: - Life Cycle
    
    public override required init() {
        super.init()
        customRenderActive = true
        customRenderDelegate = self
    }
    
    // MARK: Delay
    
    public func customRender(_ texture: MTLTexture, with commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if cachedTextures.count > 0 {
            cachedTextures.remove(at: 0)
        }
        while delayFrames != cachedTextures.count {
            if cachedTextures.count < delayFrames {
                cachedTextures.append(texture)
            } else {
                cachedTextures.remove(at: 0)
            }
        }
        return cachedTextures.first ?? texture
    }
    
}

public extension PIXOut {
    
    func _delay(frames: Int) -> DelayPIX {
        let delayPix = DelayPIX()
        delayPix.name = ":delay:"
        delayPix.inPix = self as? PIX & PIXOut
        delayPix.delayFrames = frames
        return delayPix
    }
    
}
