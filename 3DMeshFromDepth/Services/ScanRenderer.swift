//
//  ScanRenderer.swift
//  3DMeshFromDepth

import MetalKit
import ARKit

class ScanRenderer {
    
    // MARK: - Properties
    
    private var pointsCpuBuffer = [PointCPU]()
    var isSavingFile = false
    var shouldCapture = false
    
    var pointsCount = 0
    private let maxPointsInCloud = 20_000_000
    
    var numGridSamplePoints = 196_608
    
    private let pointSizeInPixels: Float = 1
    
    private let deviceOrientation = UIInterfaceOrientation.portrait
    
    private let cameraRotationThreshold = cos(0 * .degreesToRadian)
    private let cameraTranslationThreshold: Float = pow(0.00, 2)
    
    private let maxCommandBuffersInQueue = 5
    
    private lazy var rotateToARCamera = Self.makeRotateToARCameraMatrix(with: self.deviceOrientation)
    private let session: ARSession
    
    private let device: MTLDevice
    private let library: MTLLibrary
    private let renderDestinationView: RenderDestinationView
    private var commandQueue: MTLCommandQueue
    
    private let relaxedStencilState: MTLDepthStencilState
    private let depthStencilState: MTLDepthStencilState
    
    private lazy var unprojectPipelineState = self.makeUnprojectionPipelineState()!
    private lazy var rgbPipelineState = self.makeRGBPipelineState()!
    private lazy var pointPipelineState = self.makePointPipelineState()!
    
    private lazy var textureCache = self.makeTextureCacheFromImage()
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var depthTexture: CVMetalTexture?
    
    private var currentBufferIndex = 0
    
    private var viewportSize = CGSize()
    
    private lazy var gridSamplePointsBuffer = ScanMTLBuffer<Float2>(device: self.device,
                                                                    array: self.makeGridSamplePoints(),
                                                                    index: gridPoints.rawValue, options: [])
    
    private lazy var rgbUniformsBuffer: RGBUniforms = {
        var uniforms = RGBUniforms()
        uniforms.radius = 0
        uniforms.viewToCamera.copy(from: self.viewToCamera)
        uniforms.viewRatio = Float(self.viewportSize.width / self.viewportSize.height)
        return uniforms
    }()
    private var rgbUniformsBuffers = [ScanMTLBuffer<RGBUniforms>]()
    
    private lazy var pointCloudUniformsBuffer: PointCloudUniforms = {
        var uniforms = PointCloudUniforms()
        uniforms.maxPoints = Int32(self.maxPointsInCloud)
        uniforms.pointSize = self.pointSizeInPixels
        uniforms.cameraResolution = self.cameraResolution
        return uniforms
    }()
    private var pointCloudUniformsBuffers = [ScanMTLBuffer<PointCloudUniforms>]()
    
    private var pointsBuffer: ScanMTLBuffer<PointUniforms>
    private var currentPointIndex = 0
    private var currentPointCount = 0
    
    private var sampleFrame: ARFrame { self.session.currentFrame! }
    private lazy var cameraResolution = Float2(Float(self.sampleFrame.camera.imageResolution.width), Float(self.sampleFrame.camera.imageResolution.height))
    private lazy var viewToCamera = self.sampleFrame.displayTransform(for: self.deviceOrientation, viewportSize: self.viewportSize).inverted()
    private lazy var lastCameraTransform = self.sampleFrame.camera.transform
    
    // MARK: - Init
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationView) {
        self.session = session
        self.device = device
        self.renderDestinationView = renderDestination
        self.library = device.makeDefaultLibrary()!
        self.commandQueue = device.makeCommandQueue()!
        
        // Init buffers.
        for _ in 0 ..< self.maxCommandBuffersInQueue {
            self.rgbUniformsBuffers.append(.init(device: device, count: 1, index: 0))
            self.pointCloudUniformsBuffers.append(.init(device: device, count: 1, index: pointCloudUniforms.rawValue))
        }
        self.pointsBuffer = .init(device: device, count: self.maxPointsInCloud, index: pointUniforms.rawValue)
        
        // rbg does not need to read/write depth
        let relaxedStateDescriptor = MTLDepthStencilDescriptor()
        self.relaxedStencilState = device.makeDepthStencilState(descriptor: relaxedStateDescriptor)!
        
        // Setup depth test for point cloud.
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .lessEqual
        depthStateDescriptor.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthStateDescriptor)!
    }
    
    // MARK: - Methods
    
    func drawRectResized(size: CGSize) {
        self.viewportSize = size
    }
    
    private func updateCapturedImageTextures(for frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return
        }
        
        // Create two textures - Y and CbCr, from the provided frame's captured image.
        self.capturedImageTextureY = self.makeTexture(from: pixelBuffer, with: .r8Unorm, at: 0)
        self.capturedImageTextureCbCr = self.makeTexture(from: pixelBuffer, with: .rg8Unorm, at: 1)
    }
    
    private func updateDepthTextures(frame: ARFrame) -> Bool {

        if (frame.capturedDepthData != nil) {
            let capturedFrame = frame
            return self.captureImages(frame: capturedFrame)
        } else {
            return false
        }
    }
    
    func captureImages(frame: ARFrame) -> Bool {
        guard let depthMap = frame.capturedDepthData?.depthDataMap else {
            print("Error getting depthMap")
            return false
        }
        
        self.depthTexture = self.makeTexture(from: depthMap, with: .r32Float, at: 0)
        
        return true
    }
    
    private func updateData(in frame: ARFrame) {
        let camera = frame.camera
        let cameraIntrinsicsInversed = camera.intrinsics.inverse
        let viewMatrix = camera.viewMatrix(for: self.deviceOrientation)
        let viewMatrixInversed = viewMatrix.inverse
        let projectionMatrix = camera.projectionMatrix(for: self.deviceOrientation, viewportSize: self.viewportSize, zNear: 0.001, zFar: 0)
        self.pointCloudUniformsBuffer.viewProjectionMatrix = projectionMatrix * viewMatrix
        self.pointCloudUniformsBuffer.localToWorld = viewMatrixInversed * self.rotateToARCamera
        self.pointCloudUniformsBuffer.cameraIntrinsicsInversed = cameraIntrinsicsInversed
    }
    
    //*********************
    func captureStatus() {
        self.shouldCapture.toggle()
    }
    
    //******************
    
    func renderFrame() {
        guard let currentFrame = self.session.currentFrame,
              let renderDescriptor = self.renderDestinationView.currentRenderPassDescriptor,
              let commandBuffer = self.commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {
            return
        }
        
        self.updateData(in: currentFrame)
        self.updateCapturedImageTextures(for: currentFrame)
        
        // Handle buffer rotating.
        self.currentBufferIndex = (self.currentBufferIndex + 1) % self.maxCommandBuffersInQueue
        self.pointCloudUniformsBuffers[self.currentBufferIndex][0] = self.pointCloudUniformsBuffer
        
//        if self.shouldAccumulatePoints(in: currentFrame),
//           self.updateDepthTextures(frame: currentFrame) {
//            self.accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
//        }
        // changes new
        // **********************
        if (self.shouldCapture && self.updateDepthTextures(frame: currentFrame)) {
            self.accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
        }

        // **********************
        
        // Check and render rgb camera image.
        if self.rgbUniformsBuffer.radius > 0 {
            var retainingTextures = [self.capturedImageTextureY, self.capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler { buffer in
                retainingTextures.removeAll()
            }
            self.rgbUniformsBuffers[self.currentBufferIndex][0] = self.rgbUniformsBuffer
            
            renderEncoder.setDepthStencilState(self.relaxedStencilState)
            renderEncoder.setRenderPipelineState(self.rgbPipelineState)
            renderEncoder.setVertexBuffer(self.rgbUniformsBuffers[self.currentBufferIndex])
            renderEncoder.setFragmentBuffer(self.rgbUniformsBuffers[self.currentBufferIndex])
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(self.capturedImageTextureY!), index: Int(textureY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(self.capturedImageTextureCbCr!), index: Int(textureCbCr.rawValue))
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        
        renderEncoder.setDepthStencilState(self.depthStencilState)
        renderEncoder.setRenderPipelineState(self.pointPipelineState)
        renderEncoder.setVertexBuffer(self.pointCloudUniformsBuffers[self.currentBufferIndex])
        renderEncoder.setVertexBuffer(self.pointsBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: self.currentPointCount)
        
        renderEncoder.endEncoding()
        commandBuffer.present(self.renderDestinationView.currentDrawable!)
        commandBuffer.commit()
    }
    
    private func shouldAccumulatePoints(in frame: ARFrame) -> Bool {
        let cameraTransform = frame.camera.transform
        return self.currentPointCount == 0
        || dot(cameraTransform.columns.2, self.lastCameraTransform.columns.2) <= self.cameraRotationThreshold
        || distance_squared(cameraTransform.columns.3, self.lastCameraTransform.columns.3) >= self.cameraTranslationThreshold
    }
    
    private func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer, renderEncoder: MTLRenderCommandEncoder) {
//        self.pointCloudUniformsBuffer.pointCloudCurrentIndex = Int32(self.currentPointIndex)
        self.pointCloudUniformsBuffer.pointCloudCurrentIndex = Int32(0)
        
        var retainingTextures = [self.capturedImageTextureY, self.capturedImageTextureCbCr, self.depthTexture]
        
        commandBuffer.addCompletedHandler { buffer in
            retainingTextures.removeAll()
            var i = self.pointsCpuBuffer.count
            while (i < self.maxPointsInCloud && self.pointsBuffer[i].position != simd_float3(0.0,0.0,0.0)) {

                let position = self.pointsBuffer[i].position
                let color = self.pointsBuffer[i].color
                if !(position.x.isNaN || position.y.isNaN || position.z.isNaN) && position.z > -0.4 {

                    self.pointsCount += 1
                    self.pointsCpuBuffer.append(PointCPU(position: position, color: color))
                }

                i += 1
            }
        }
        
        renderEncoder.setDepthStencilState(self.relaxedStencilState)
        renderEncoder.setRenderPipelineState(self.unprojectPipelineState)
        renderEncoder.setVertexBuffer(self.pointCloudUniformsBuffers[self.currentBufferIndex])
        renderEncoder.setVertexBuffer(self.pointsBuffer)
        renderEncoder.setVertexBuffer(self.gridSamplePointsBuffer)
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(self.capturedImageTextureY!), index: Int(textureY.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(self.capturedImageTextureCbCr!), index: Int(textureCbCr.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(self.depthTexture!), index: Int(textureDepth.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: self.gridSamplePointsBuffer.count)
        
        self.currentPointIndex = (self.currentPointIndex + self.gridSamplePointsBuffer.count) % self.maxPointsInCloud
        self.currentPointCount = min(self.currentPointCount + self.gridSamplePointsBuffer.count, self.maxPointsInCloud)
        self.lastCameraTransform = frame.camera.transform
    }
}

// MARK: - Point cloud saving.

extension ScanRenderer {
    
    func saveToPly(_ completion: @escaping (Bool) -> ()) {
        
        
        guard !self.isSavingFile else { return }
        
        guard !self.pointsCpuBuffer.isEmpty else { return }
        
        DispatchQueue.global().async {
            self.isSavingFile = true
            
            do {
                try PlyMesh.writeToFile(pointsCpuBuffer: &self.pointsCpuBuffer,
                                        pointsCount: self.pointsCount)
                completion(true)
            } catch { }
            
            self.isSavingFile = false
        }
    }
}

// MARK: - Metal shader.

private extension ScanRenderer {
    
    func makeUnprojectionPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "unprojectVertex") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.isRasterizationEnabled = false
        descriptor.depthAttachmentPixelFormat = self.renderDestinationView.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = self.renderDestinationView.colorPixelFormat
        
        return try? self.device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makeRGBPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = self.library.makeFunction(name: "rgbVertex"),
              let fragmentFunction = self.library.makeFunction(name: "rgbFragment") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = self.renderDestinationView.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = self.renderDestinationView.colorPixelFormat
        
        return try? self.device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makePointPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = self.library.makeFunction(name: "pointVertex"),
              let fragmentFunction = self.library.makeFunction(name: "pointFragment") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = self.renderDestinationView.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = self.renderDestinationView.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try? self.device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makeGridSamplePoints() -> [Float2] {
        let gridArea = self.cameraResolution.x * self.cameraResolution.y
        let spacing = sqrt(gridArea / Float(self.numGridSamplePoints))
        let deltaX = Int(round(self.cameraResolution.x / spacing))
        let deltaY = Int(round(self.cameraResolution.y / spacing))
        
        var points = [Float2]()
        for gridY in 0 ..< deltaY {
            let alternatingOffsetX = Float(gridY % 2) * spacing / 2
            for gridX in 0 ..< deltaX {
                let cameraPoint = Float2(alternatingOffsetX + (Float(gridX) + 0.5) * spacing, (Float(gridY) + 0.5) * spacing)
                points.append(cameraPoint)
            }
        }
        return points
    }
    
    func makeTextureCacheFromImage() -> CVMetalTextureCache {
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, self.device, nil, &cache)
        return cache
    }
    
    func makeTexture(from pixelBuffer: CVPixelBuffer, with pixelFormat: MTLPixelFormat, at planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, self.textureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        if status != kCVReturnSuccess { texture = nil }
        return texture
    }
    
    static func cameraToDisplayRotation(with orientation: UIInterfaceOrientation) -> Int {
        switch orientation {
        case .landscapeLeft:
            return 180
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return -90
        default:
            return 0
        }
    }
    
    static func makeRotateToARCameraMatrix(with orientation: UIInterfaceOrientation) -> matrix_float4x4 {
        let flipYZ = matrix_float4x4(
            [1, 0, 0, 0],
            [0, -1, 0, 0],
            [0, 0, -1, 0],
            [0, 0, 0, 1] )
        
        let rotationAngle = Float(self.cameraToDisplayRotation(with: orientation)) * .degreesToRadian
        return flipYZ * matrix_float4x4(simd_quaternion(rotationAngle, Float3(0, 0, 1)))
    }
}
