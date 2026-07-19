#ifndef RAYTRACING_SAMPLE_INCLUDED
#define RAYTRACING_SAMPLE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/DynamicScalingClamping.hlsl"

TEXTURE2D_X_FLOAT(_CameraDepthTexture);
float4 _CameraDepthTexture_TexelSize;

TEXTURE2D_X_FLOAT(_CameraNormalsTexture);
SAMPLER(sampler_CameraNormalsTexture);

void SampleSurfaceData(float2 uv, out float outDepth, out float3 outNormal)
{
    uv = ClampAndScaleUVForBilinear(UnityStereoTransformScreenSpaceTex(uv), _CameraDepthTexture_TexelSize.xy);
    float deviceDepth = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_PointClamp, uv, 0).r;
    #if !UNITY_REVERSED_Z
    deviceDepth = deviceDepth * 2.0 - 1.0;
    #endif

    float3 normal = SAMPLE_TEXTURE2D_X_LOD(_CameraNormalsTexture, sampler_CameraNormalsTexture, uv, 0).xyz;

    #if defined(_GBUFFER_NORMALS_OCT)
    float2 remappedOctNormalWS = Unpack888ToFloat2(normal); // values between [ 0,  1]
    float2 octNormalWS = remappedOctNormalWS.xy * 2.0 - 1.0;    // values between [-1, +1]
    normal = UnpackNormalOctQuadEncode(octNormalWS);
    #endif

    outNormal = normal;
    outDepth = deviceDepth;
}

#endif
