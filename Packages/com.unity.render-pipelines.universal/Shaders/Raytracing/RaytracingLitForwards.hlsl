#include "Packages/com.unity.render-pipelines.universal/Shaders/Raytracing/RaytracingLighting.hlsl"

[shader("anyhit")]
void anyHit (inout RayPayload rayPayload , in AttributeData attributeData)
{
    #ifdef _ALPHATEST_ON
        IntersectionVertex currentvertex;
        GetCurrentIntersectionVertex(attributeData, currentvertex);

        half3 worldPos = WorldRayOrigin() + RayTCurrent()* WorldRayDirection();
        float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
        float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));

        float LOD = RayCalcLOD(currentvertex, rayPayload.rayConeWidth, WorldRayDirection(), worldNormal);

        half2 uv = TRANSFORM_TEX(currentvertex.texCoord0, _BaseMap);

        half alpha = _BaseColor.a*SampleTex2D(_BaseMap, sampler_BaseMap, uv, _BaseMap_ST.xy, LOD).a;

        if(alpha <= _Cutoff)
            IgnoreHit();
    #endif
}

[shader("closesthit")]
void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
{
    float3 debug = 0;

    float3 rayOrigin = WorldRayOrigin();
    float3 rayDir = WorldRayDirection();
    float3 worldPos = rayOrigin + RayTCurrent()* rayDir;
    // compute vertex data on ray/triangle intersection
    IntersectionVertex currentvertex;
    GetCurrentIntersectionVertex(attributeData, currentvertex, rayDir);
    float2 uv = TRANSFORM_TEX(currentvertex.texCoord0, _BaseMap);

    float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
    float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));

    rayPayload.rayConeWidth += rayPayload.rayConeSpreadAngle*RayTCurrent();

    float LOD = RayCalcLOD(currentvertex, rayPayload.rayConeWidth, rayDir, worldNormal);

    SurfaceData surfaceData;
    InitializePlasticLitSurfaceData(uv, LOD, surfaceData);

    if(rayPayload.depth == 0 && !RayShouldReflect(surfaceData.smoothness, rayPayload))
    {
        return;
    }

    #ifdef _NORMALMAP
    RayCalcNormalMap(surfaceData.normalTS, currentvertex, worldNormal);
    #endif
    float3 normalWS = NormalizeNormalPerPixel(worldNormal);
    normalWS *= currentvertex.frontFace ? 1 : -1;

    float3 reflectDir = reflect(rayDir, normalWS);

    if(rayPayload.depth == 0)
    {
        #ifdef _REFLECTION_SCREEN
        half3 color = RayReflectionCalc(worldPos, reflectDir, rayPayload);
        if (color.x < 0.h)
        {
            half roughness = 1.h - surfaceData.smoothness;
            if (_REFLECTION_PROBE_BLENDING)
            {
                color = CalculateIrradianceFromReflectionProbes(reflectDir, worldPos, roughness, half2(1.f, 1.f));
            }
            else
            {
                if (_REFLECTION_PROBE_BOX_PROJECTION)
                {
                    #if defined(REFLECTION_PROBE_ROTATION)
                    float3 probeCenterPosWS0 = unity_SpecCube0_BoxMin.xyz + (unity_SpecCube0_BoxMax.xyz - unity_SpecCube0_BoxMin.xyz) / 2;
                    float3 rotPosWS0 = RotateVectorByQuat(unity_SpecCube0_Rotation, positionWS - probeCenterPosWS0) + probeCenterPosWS0;
                    half3 rotReflectVector0 = RotateVectorByQuat(unity_SpecCube0_Rotation, reflectVector);
                    float4 inverseRotation0 = -unity_SpecCube0_Rotation;
                    inverseRotation0.w = -inverseRotation0.w;
                    reflectVector = BoxProjectedCubemapDirection(rotReflectVector0, rotPosWS0, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
                    reflectVector = RotateVectorByQuat(inverseRotation0, reflectVector);
                    #else
                    reflectDir = BoxProjectedCubemapDirection(reflectDir, worldPos, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
                    #endif
                }
                half mip = PerceptualRoughnessToMipmapLevel(roughness);
                half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectDir, mip));

                color = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
            }
        }
        rayPayload.color = color;
        #endif

        Light mainLight = GetMainLight();

        #ifdef _MAIN_LIGHT_SHADOWS_SCREEN
            rayPayload.shadow = CalculateShadowAttenuation(inputData.positionWS, mainLight.direction, 100.f);

            /*#if defined(_ADDITIONAL_LIGHTS)
            uint pixelLightCount = GetAdditionalLightsCount();

            LIGHT_LOOP_BEGIN(pixelLightCount)
                half4 lightVector = GetAdditionalLightDistance(lightIndex, inputData.positionWS);

                if(lightVector.w > 0.f)
                {
                    half shadow = CalculateShadowAttenuation(inputData.positionWS, normalize(lightVector.xyz), length(lightVector.xyz));
                    rayPayload.shadow *= max(shadow, lightVector.w);
                }
            LIGHT_LOOP_END
            #endif*/
        #endif

        return;
    }

    InputData inputData;
    inputData = (InputData)0;
    inputData.positionWS = worldPos;
    inputData.viewDirectionWS = normalize(-rayDir);
    inputData.normalizedScreenSpaceUV = (float2)DispatchRaysIndex().xy/(float2)DispatchRaysDimensions().xy;
    inputData.normalWS = normalWS;

    #if defined(MAIN_LIGHT_CALCULATE_SHADOWS)
    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
    #else
    inputData.shadowCoord = float4(0, 0, 0, 0);
    #endif

    //inputData.bakedGI = _GlossyEnvironmentColor.xyz;
    // inputData.bakedGI = SampleSH(inputData.normalWS);
    inputData.bakedGI = SAMPLE_GI(half2(0.f, half2(0.f)), inputData.positionWS, inputData.normalWS);

    rayPayload.color = RayUniversalFragmentPBR(inputData, surfaceData, rayPayload);

    // stop if we have reached max recursion depth
    if(rayPayload.depth + 1 >= gMaxDepth)
        return;
}
