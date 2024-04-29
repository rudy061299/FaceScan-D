//
//  ScanMTLBuffer.swift
//  3DMeshFromDepth

import MetalKit

// MTLBuffer extension for safe access and assignment to it underlying contents.
struct ScanMTLBuffer<Element>: Resource {
    
    fileprivate let buffer: MTLBuffer
    
    fileprivate let index: Int
    
    let count: Int
    
    var stride: Int {
        MemoryLayout<Element>.stride
    }

    init(device: MTLDevice, count: Int, index: UInt32, label: String? = nil, options: MTLResourceOptions = []) {
        guard let buffer = device.makeBuffer(length: MemoryLayout<Element>.stride * count, options: options) else {
            fatalError("Failed to create MTLBuffer.")
        }
        self.buffer = buffer
        self.buffer.label = label
        self.count = count
        self.index = Int(index)
    }
    
    init(device: MTLDevice, array: [Element], index: UInt32, options: MTLResourceOptions = []) {
        guard let buffer = device.makeBuffer(bytes: array, length: MemoryLayout<Element>.stride * array.count, options: .storageModeShared) else {
            fatalError("Failed to create MTLBuffer")
        }
        self.buffer = buffer
        self.count = array.count
        self.index = Int(index)
    }
    
    // Replace buffer memory at index with value.
    func assign<T>(_ value: T, at index: Int = 0) {
        precondition(index <= count - 1, "Index \(index) is greater than maximum allowable index of \(count - 1) for this buffer.")
        withUnsafePointer(to: value) {
            buffer.contents().advanced(by: index * stride).copyMemory(from: $0, byteCount: stride)
        }
    }
    
    // Replace buffer memory with array.
    func assign<Element>(with array: [Element]) {
        let byteCount = array.count * stride
        precondition(byteCount == buffer.length, "Mismatch between the byte count of the array's contents and the MTLBuffer length.")
        buffer.contents().copyMemory(from: array, byteCount: byteCount)
    }
    
    // Return copy of value at index in buffer.
    subscript(index: Int) -> Element {
        get {
            precondition(stride * index <= buffer.length - stride, "This buffer is not large enough to have an element at the index: \(index)")
            return buffer.contents().advanced(by: index * stride).load(as: Element.self)
        }
        
        set {
            assign(newValue, at: index)
        }
    }
    
}

extension MTLRenderCommandEncoder {
    
    func setVertexBuffer<T>(_ vertexBuffer: ScanMTLBuffer<T>, offset: Int = 0) {
        setVertexBuffer(vertexBuffer.buffer, offset: offset, index: vertexBuffer.index)
    }
    
    func setFragmentBuffer<T>(_ fragmentBuffer: ScanMTLBuffer<T>, offset: Int = 0) {
        setFragmentBuffer(fragmentBuffer.buffer, offset: offset, index: fragmentBuffer.index)
    }
    
    func setVertexResource<R: Resource>(_ resource: R) {
        if let buffer = resource as? ScanMTLBuffer<R.Element> {
            self.setVertexBuffer(buffer)
        }
        
        if let texture = resource as? Texture {
            setVertexTexture(texture.texture, index: texture.index)
        }
    }
    
    func setFragmentResource<R: Resource>(_ resource: R) {
        if let buffer = resource as? ScanMTLBuffer<R.Element> {
            self.setFragmentBuffer(buffer)
        }

        if let texture = resource as? Texture {
            setFragmentTexture(texture.texture, index: texture.index)
        }
    }
}
