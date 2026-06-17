#ifndef RAYTRACING_HELPERS_INCLUDED
#define RAYTRACING_HELPERS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/Shaders/Raytracing/RaytraceCommon.hlsl"

bool RayShouldReflect(float reflection, RayPayload rayPayload)
{
    bool shouldReflect = false;

    if(gMaxReflectDepth == 0 || rayPayload.depth >= gMaxReflectDepth)
        return false;

    return true;

    #ifndef REFLECTION_OVERRIDE
        if(reflection > .5f)
            shouldReflect = true;
        else if(reflection > .35f)
            shouldReflect = rayPayload.depth < max(gMaxReflectDepth-1, 1);
    #else
        shouldReflect = true;
    #endif

    return shouldReflect;
}

float RayCalcLOD(IntersectionVertex vertex, float coneWidth, float3 rayDir, float3 normal)
{
    float texCoordArea = vertex.texCoord0Area;
    float triangleArea = vertex.triangleArea;

    float lambda = log2(texCoordArea/triangleArea)*.5;
    lambda += log2(abs(coneWidth));
    lambda -= log2(abs(dot(rayDir, normal)));

    return lambda-1.f;
}

void RayCalcNormalMap(float3 tangentNormal, IntersectionVertex currentvertex, inout float3 worldNormal)
{
    float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();

    float3 worldBinormal = normalize(mul(objectToWorld, cross(currentvertex.normalOS, currentvertex.tangentOS)));
    float3 worldTangent = normalize(mul(objectToWorld, currentvertex.tangentOS));

    float3x3 TBN = float3x3(normalize(worldTangent), normalize(worldBinormal), normalize(worldNormal));
    TBN = transpose(TBN);

    worldNormal = mul(TBN, tangentNormal);
}
#endif
