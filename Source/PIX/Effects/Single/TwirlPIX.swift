//
//  TwirlPIX.swift
//  Pixels
//
//  Created by Hexagons on 2018-08-11.
//  Open Source - MIT License
//

public class TwirlPIX: PIXSingleEffect {
    
    override open var shader: String { return "effectSingleTwirlPIX" }
    
    // MARK: - Public Properties
    
    public var strength: LiveFloat = 1.0
    
    // MARK: - Property Helpers
    
    override var liveValues: [LiveValue] {
        return [strength]
    }
    
    // MARK: - Life Cycle
    
    public override init() {
        super.init()
        extend = .mirror
    }
    
}

public extension PIXOut {
    
    func _twirl(_ strength: LiveFloat) -> TwirlPIX {
        let twirlPix = TwirlPIX()
        twirlPix.name = ":twirl:"
        twirlPix.inPix = self as? PIX & PIXOut
        twirlPix.strength = strength
        return twirlPix
    }
    
}
