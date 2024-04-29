//
//  PlyMesh.swift
//  3DMeshFromDepth

import Foundation

class PlyMesh {
    
    static func writeToFile(pointsCpuBuffer: inout [PointCPU], pointsCount: Int) throws {
        
//        PointsSaver.shared.save(text: "pointsCpuBuffer: \(pointsCpuBuffer.map { $0.position })", withFileName: "points.txt")
        
        let fileName = "Front_scan"
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let date = Date().description(with: .current)
        
        let plyFile = documentsDirectory.appendingPathComponent("\(fileName)_\(date).ply", isDirectory: false)
        FileManager.default.createFile(atPath: plyFile.path, contents: nil, attributes: nil)
        
        let format = "ascii"
        
        var fileString = ""
        let headers = [
            "ply",
            "comment Created by SceneX (IOS)",
            "format \(format) 1.0",
            "element vertex \(pointsCount)",
            "property float x",
            "property float y",
            "property float z",
            "property uchar red",
            "property uchar green",
            "property uchar blue",
            "property uchar alpha",
            "element face 0",
            "property list uchar int vertex_indices",
            "end_header"]
        print("point count inside saving \(headers[3])")
        for header in headers { fileString += header + "\r\n" }
        
        for point in pointsCpuBuffer {
            
            if (point.position.x.isNaN || point.position.y.isNaN || point.position.z.isNaN) { continue }
            
            let x = point.position.x
            let y = point.position.y
            let z = point.position.z
            
            let colors = point.color
            let red = self.arrangeColorByte(color: colors.x)
            let green = self.arrangeColorByte(color: colors.y)
            let blue = self.arrangeColorByte(color: colors.z)
            let alpha = UInt8(255)
            
            let pointData = "\(x) \(y) \(z) \(Int(red)) \(Int(green)) \(Int(blue)) \(Int(alpha))"
            fileString += pointData
            fileString += "\r\n"
            
        }
        
        do {
            try fileString.write(to: plyFile, atomically: true, encoding: String.Encoding.ascii)
        }
        catch {
            print("Failed to write PLY file", error)
        }
        
//        try fileString.write(to: plyFile, atomically: true, encoding: .ascii)
//        
//        try writeBinary(file: plyFile, format: format, pointsCPUBuffer: &pointsCpuBuffer)
        
        // original
//        let format = "binary_little_endian"
//        
//        var headersString = ""
//        let headers = [
//            "ply",
//            "comment Created by SceneX (IOS)",
//            "format \(format) 1.0",
//            "element vertex \(pointsCount)",
//            "property float x",
//            "property float y",
//            "property float z",
//            "property uchar red",
//            "property uchar green",
//            "property uchar blue",
//            "property uchar alpha",
//            "element face 0",
//            "property list uchar int vertex_indices",
//            "end_header"]
//        
//        for header in headers { headersString += header + "\r\n" }
//        try headersString.write(to: plyFile, atomically: true, encoding: .ascii)
//        
//        try writeBinary(file: plyFile, format: format, pointsCPUBuffer: &pointsCpuBuffer)
    }
    
    private static func writeBinary(file: URL, format: String, pointsCPUBuffer: inout [PointCPU]) throws -> Void {
        let fileHandle = try! FileHandle(forWritingTo: file)
        fileHandle.seekToEndOfFile()
        var data = Data()
        
        for point in pointsCPUBuffer {
//            print("x y z position")
//            print(point.position.x.isNaN)
//            print(point.position.y.isNaN)
//            print(point.position.z.isNaN)
            if (point.position.x.isNaN || point.position.y.isNaN || point.position.z.isNaN) { continue }
            
            var x = point.position.x.bitPattern.littleEndian
            data.append(withUnsafePointer(to: &x) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            
            var y = point.position.y.bitPattern.littleEndian
            data.append(withUnsafePointer(to: &y) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            
            var z = point.position.z.bitPattern.littleEndian
            data.append(withUnsafePointer(to: &z) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            
            let colors = point.color
            var red = self.arrangeColorByte(color: colors.x).littleEndian
            data.append(withUnsafePointer(to: &red) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            
            var green = self.arrangeColorByte(color: colors.y).littleEndian
            data.append(withUnsafePointer(to: &green) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            
            var blue = self.arrangeColorByte(color: colors.z).littleEndian
            data.append(withUnsafePointer(to: &blue) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            
            var alpha = UInt8(255).littleEndian
            data.append(withUnsafePointer(to: &alpha) {
                Data(buffer: UnsafeBufferPointer(start: $0, count: 1))
            })
            
        }
        fileHandle.write(data)
        fileHandle.closeFile()
        print("File location")
        print(file)
        print("file handle")
        print(fileHandle)

    }
    
    private static func arrangeColorByte(color: simd_float1) -> UInt8 {
        let absColor = abs(Int16(color))
        return absColor <= 255 ? UInt8(absColor) : UInt8(255)
    }
}
