//
//  PointCPU.swift
//  3DMeshFromDepth

import Foundation

class PointCPU {
   var position: simd_float3
   var color: simd_float3
   
    init(position: simd_float3, color: simd_float3) {
       self.position = position
       self.color = color * 255
   }
}
