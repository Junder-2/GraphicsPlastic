#include "Packages/com.unity.render-pipelines.universal/Shaders/Raytracing/RaytracingLighting.hlsl"

[shader("anyhit")]
void anyHit(inout RayPayload rayPayload, in AttributeData attributeData)
{
    float coneWidth = rayPayload.rayConeWidth;
    rayPayload.rayConeWidth += rayPayload.rayConeSpreadAngle*RayTCurrent();

    bool isFrontFace;
    Varyings input = BuildVaryings(rayPayload, attributeData, isFrontFace);
    SurfaceDescription surfaceDescription = BuildSurfaceDescription(input);
    rayPayload.rayConeWidth = coneWidth;

#ifdef _RENDER_FACE_BACK
    if (isFrontFace)
    {
        IgnoreHit();
        return;
    }
#elif !defined(_RENDER_FACE_DOUBLE)
    if (!isFrontFace)
    {
        IgnoreHit();
        return;
    }
#endif

#ifdef _ALPHATEST_ON
    if(surfaceDescription.Alpha <= surfaceDescription.AlphaClipThreshold)
        IgnoreHit();
#endif
}

[shader("closesthit")]
void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
{
    // rayPayload.color = half3(1.0f, 0.0f, 0.0f);
    // return;
    float3 debug = 0;

    float3 rayDir = WorldRayDirection();

    rayPayload.rayConeWidth += rayPayload.rayConeSpreadAngle*RayTCurrent();

    bool isFrontFace;
    Varyings input = BuildVaryings(rayPayload, attributeData, isFrontFace);

    SurfaceDescription surfaceDescription = BuildSurfaceDescription(input);

    if(!RayShouldReflect(surfaceDescription.Smoothness, rayPayload))
    {
        return;
    }

#if defined(_SURFACE_TYPE_TRANSPARENT)
    bool isTransparent = true;
#else
    bool isTransparent = false;
#endif

#if defined(_ALPHATEST_ON)
    // half alpha = AlphaDiscard(surfaceDescription.Alpha, surfaceDescription.AlphaClipThreshold);
    half alpha = RayAlphaClip(surfaceDescription.Alpha, surfaceDescription.AlphaClipThreshold);
#elif defined(_SURFACE_TYPE_TRANSPARENT)
    half alpha = surfaceDescription.Alpha;
#else
    half alpha = half(1.0);
#endif

#if defined(LOD_FADE_CROSSFADE) && USE_UNITY_CROSSFADE
    LODFadeCrossFade(unpacked.positionCS);
#endif

#ifdef _SPECULAR_SETUP
    float3 specular = surfaceDescription.Specular;
    float metallic = 0;
#else
    float3 specular = 0;
    float metallic = surfaceDescription.Metallic;
#endif

    half3 normalTS = half3(0, 0, 0);
#if defined(_NORMALMAP) && defined(_NORMAL_DROPOFF_TS)
    normalTS = surfaceDescription.NormalTS;
#endif

    SurfaceData surface;
    surface.albedo              = surfaceDescription.BaseColor;
    surface.metallic            = saturate(metallic);
    surface.specular            = specular;
    surface.smoothness          = saturate(surfaceDescription.Smoothness),
    surface.occlusion           = surfaceDescription.Occlusion,
    surface.emission            = surfaceDescription.Emission,
    surface.alpha               = saturate(alpha);
    surface.normalTS            = normalTS;
    surface.clearCoatMask       = 0;
    surface.clearCoatSmoothness = 1;

    // PLASTIC
    surface.subsurfaceColor     = 0;
    surface.subsurfaceStrength  = 0;
    surface.extraProp           = 1;

#ifdef _SUBSURFACECOLOR
    surface.subsurfaceColor = surfaceDescription.SubsurfaceColor;
    surface.subsurfaceStrength = surfaceDescription.SubsurfaceStrength;
#endif

#ifdef _HAS_SPECULAR_FACTOR
    surface.extraProp = surfaceDescription.SpecularFactor;
#endif

#ifdef _CLEARCOAT
    surface.clearCoatMask       = saturate(surfaceDescription.CoatMask);
    surface.clearCoatSmoothness = saturate(surfaceDescription.CoatSmoothness);
#endif

    surface.albedo = AlphaModulate(surface.albedo, surface.alpha);

    // #ifdef _NORMALMAP
    // RayCalcNormalMap(surface.normalTS, currentvertex, worldNormal);
    // #endif


    InputData inputData;
    inputData = (InputData)0;
    inputData.positionWS = input.positionWS;
#ifdef _NORMALMAP
    float crossSign = (input.tangentWS.w > 0.0 ? 1.0 : -1.0) * GetOddNegativeScale();
    float3 bitangent = crossSign * cross(input.normalWS.xyz, input.tangentWS.xyz);
    inputData.tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);
    #if _NORMAL_DROPOFF_TS
        inputData.normalWS = TransformTangentToWorld(surfaceDescription.NormalTS, inputData.tangentToWorld);
    #elif _NORMAL_DROPOFF_OS
        inputData.normalWS = TransformObjectToWorldNormal(surfaceDescription.NormalOS);
    #elif _NORMAL_DROPOFF_WS
        inputData.normalWS = surfaceDescription.NormalWS;
    #endif
#else
    inputData.normalWS = input.normalWS;
#endif
    // inputData.normalWS = normalize(inputData.normalWS);

    float3 reflectDir = reflect(rayDir, inputData.normalWS);

//     if(rayPayload.depth == 0)
//     {
//         #ifdef _REFLECTION_SCREEN
//         half3 color = RayReflectionCalc(inputData.positionWS, reflectDir, rayPayload);
//         if (color.x < 0.h)
//         {
//             half roughness = 1.h - surface.smoothness;
//             if (_REFLECTION_PROBE_BLENDING)
//             {
//                 color = CalculateIrradianceFromReflectionProbes(reflectDir, inputData.positionWS, roughness, half2(1.f, 1.f));
//             }
//             else
//             {
//                 if (_REFLECTION_PROBE_BOX_PROJECTION)
//                 {
//                     #if defined(REFLECTION_PROBE_ROTATION)
//                     float3 probeCenterPosWS0 = unity_SpecCube0_BoxMin.xyz + (unity_SpecCube0_BoxMax.xyz - unity_SpecCube0_BoxMin.xyz) / 2;
//                     float3 rotPosWS0 = RotateVectorByQuat(unity_SpecCube0_Rotation, positionWS - probeCenterPosWS0) + probeCenterPosWS0;
//                     half3 rotReflectVector0 = RotateVectorByQuat(unity_SpecCube0_Rotation, reflectVector);
//                     float4 inverseRotation0 = -unity_SpecCube0_Rotation;
//                     inverseRotation0.w = -inverseRotation0.w;
//                     reflectVector = BoxProjectedCubemapDirection(rotReflectVector0, rotPosWS0, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
//                     reflectVector = RotateVectorByQuat(inverseRotation0, reflectVector);
//                     #else
//                     reflectDir = BoxProjectedCubemapDirection(reflectDir, inputData.positionWS, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
//                     #endif
//                 }
//                 half mip = PerceptualRoughnessToMipmapLevel(roughness);
//                 half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectDir, mip));
//
//                 color = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
//             }
//         }
//         rayPayload.color = color;
//         #endif
//
//         Light mainLight = GetMainLight();
//
//         #ifdef _MAIN_LIGHT_SHADOWS_SCREEN
//             rayPayload.shadow = CalculateShadowAttenuation(inputData.positionWS, mainLight.direction, 100.f);
//
//             /*#if defined(_ADDITIONAL_LIGHTS)
//             uint pixelLightCount = GetAdditionalLightsCount();
//
//             LIGHT_LOOP_BEGIN(pixelLightCount)
//                 half4 lightVector = GetAdditionalLightDistance(lightIndex, inputData.positionWS);
//
//                 if(lightVector.w > 0.f)
//                 {
//                     half shadow = CalculateShadowAttenuation(inputData.positionWS, normalize(lightVector.xyz), length(lightVector.xyz));
//                     rayPayload.shadow *= max(shadow, lightVector.w);
//                 }
//             LIGHT_LOOP_END
//             #endif*/
//         #endif
//
//         return;
//     }

    inputData.viewDirectionWS = normalize(-rayDir);
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif

    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactorAndVertexLight.x);
    inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
#if defined(_SCREEN_SPACE_IRRADIANCE)
    inputData.bakedGI = SAMPLE_GI(_ScreenSpaceIrradiance, input.positionCS.xy);
#elif defined(DYNAMICLIGHTMAP_ON)
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.dynamicLightmapUV.xy, input.sh, inputData.normalWS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
#elif !defined(LIGHTMAP_ON) && (defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2))
    inputData.bakedGI = SAMPLE_GI(input.sh,
        GetAbsolutePositionWS(inputData.positionWS),
        inputData.normalWS,
        inputData.viewDirectionWS,
        input.positionCS.xy,
        input.probeOcclusion,
        inputData.shadowMask);
#else
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.sh, inputData.normalWS);
    inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
#endif

#if defined(DEBUG_DISPLAY)
    #if defined(DYNAMICLIGHTMAP_ON)
    inputData.dynamicLightmapUV = input.dynamicLightmapUV.xy;
    #endif
    #if defined(LIGHTMAP_ON)
    inputData.staticLightmapUV = input.staticLightmapUV;
    #else
    inputData.vertexSH = input.sh;
    #endif

    #if defined(USE_APV_PROBE_OCCLUSION)
    inputData.probeOcclusion = input.probeOcclusion;
    #endif

    inputData.positionCS = input.positionCS;
#endif

    rayPayload.color = RayUniversalFragmentPBR(inputData, surface, rayPayload).rgb;

    // stop if we have reached max recursion depth
    if(rayPayload.depth >= gMaxDepth)
        return;
}
