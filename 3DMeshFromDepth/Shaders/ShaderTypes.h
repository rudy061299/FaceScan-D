//
//  ShaderTypes.h
//  3DMeshFromDepth

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

enum TextureIndices {
    textureY = 0,
    textureCbCr = 1,
    textureDepth = 2,
    textureConfidence = 3
};

enum BufferIndices {
    pointCloudUniforms = 0,
    pointUniforms = 1,
    gridPoints = 2,
};

// Constant vertex values.
struct RGBUniforms {
    matrix_float3x3 viewToCamera;
    float viewRatio;
    float radius;
};

struct PointCloudUniforms {
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 localToWorld;
    matrix_float3x3 cameraIntrinsicsInversed;
    simd_float2 cameraResolution;
    
    float pointSize;
    int maxPoints;
    int pointCloudCurrentIndex;
};

struct PointUniforms {
    simd_float3 position;
    simd_float3 color;
};

#endif /* ShaderTypes_h */
