//
//  Texture.swift
//  3DMeshFromDepth
//

import MetalKit

protocol Resource {
    associatedtype Element
}

struct Texture: Resource {
    typealias Element = Any
    
    let texture: MTLTexture
    let index: Int
}
