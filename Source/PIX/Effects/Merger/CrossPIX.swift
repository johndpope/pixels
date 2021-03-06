//
//  CrossPIX.swift
//  Pixels
//
//  Created by Hexagons on 2018-08-21.
//  Open Source - MIT License
//

public class CrossPIX: PIXMergerEffect {
    
    override open var shader: String { return "effectMergerCrossPIX" }
    
    // MARK: - Public Properties
    
    public var fraction: LiveFloat = 0.5
    
    // MARK: - Property Helpers
    
    override var liveValues: [LiveValue] {
        return [fraction]
    }
    
//    enum CodingKeys: String, CodingKey {
//        case fraction
//    }
    
//    open override var uniforms: [CGFloat] {
//        return [fraction]
//    }
    
}

func cross(_ pixA: PIX & PIXOut, _ pixB: PIX & PIXOut, at fraction: LiveFloat) -> CrossPIX {
    let crossPix = CrossPIX()
    crossPix.name = ":cross:"
    crossPix.inPixA = pixA
    crossPix.inPixB = pixB
    crossPix.fraction = fraction
    return crossPix
}
