//
//  FreezePIX.swift
//  Pixels
//
//  Created by Anton Heestand on 2018-09-23.
//  Open Source - MIT License
//

import Metal

public class FreezePIX: PIXSingleEffect {
    
    override open var shader: String { return "nilPIX" }
    
    // MARK: - Public Properties
    
    public var freeze: LiveBool = false
    
    // MARK: - Property Helpers
    
    override var liveValues: [LiveValue] {
        return [freeze]
    }
    
    // MARK: - Life Cycle
    
    public override required init() {
        super.init()
    }
    
    // MARK: Freeze
    
    public override func setNeedsRender() {
        if !freeze.val {
            super.setNeedsRender()
        }
    }
    
}

public extension PIXOut {
    
    func _freeze(_ active: LiveBool) -> FreezePIX {
        let freezePix = FreezePIX()
        freezePix.name = ":freeze:"
        freezePix.inPix = self as? PIX & PIXOut
        freezePix.freeze = active
        return freezePix
    }
    
}
