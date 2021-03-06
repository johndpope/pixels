//
//  PIXSingleEffect.swift
//  Pixels
//
//  Created by Hexagons on 2018-07-31.
//  Open Source - MIT License
//


open class PIXSingleEffect: PIXEffect, PIXInSingle {
    
    public var inPix: (PIX & PIXOut)? { didSet { setNeedsConnect() } }
    
    // MARK: - Life Cycle
    
    public override init() {
        super.init()
    }
    
}
