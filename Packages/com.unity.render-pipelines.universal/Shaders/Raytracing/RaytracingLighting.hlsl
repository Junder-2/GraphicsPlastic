#ifndef RAYTRACING_LIGHTING_INCLUDED
#define RAYTRACING_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/Shaders/Raytracing/RaytracingHelpers.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

half CalculateShadowAttenuation(float3 worldPos, half3 lightDir, half lightDist)
{
    if(lightDist < FLT_MIN) return 1.f;
    float3 samplePos = (worldPos+lightDir*lightDist);

    half3 sampleDir = -lightDir;

    bool hit = ShadowRay(samplePos, sampleDir, .1f, (lightDist-gShadowOffset));

    return hit ? 0 : 1;
}

half3 RayReflectionCalc(float3 worldPos, half3 reflectDir, RayPayload rayPayload)
{
    RayDesc reflectRay;
    reflectRay.Origin = worldPos;
    reflectRay.Direction = normalize(reflectDir);
    reflectRay.TMin = 0.001;
    reflectRay.TMax = gClipDistance*.1;

    RayPayload reflectPayload;
    reflectPayload.color = 0;
    reflectPayload.rayConeSpreadAngle = rayPayload.rayConeSpreadAngle;
    reflectPayload.rayConeWidth = rayPayload.rayConeWidth;
    reflectPayload.randomSeed = rayPayload.randomSeed;
    reflectPayload.depth = rayPayload.depth + 1;
    reflectPayload.data = 0;

    uint flags = 0;

    flags |= RAY_FLAG_CULL_BACK_FACING_TRIANGLES;

    TraceRay(_RaytracingAccelerationStructure, flags, RAYTRACING_DEFAULT, 0, 1, 0, reflectRay, reflectPayload);

    return reflectPayload.color;
}

void RayTransparentCalc(float alpha, float3 worldPos, half3 worldNormal, float refraction, RayPayload rayPayload, inout float4 color, inout float3 reflect)
{
    float3 rayDir = WorldRayDirection();
    RayDesc transparentRay;

    int flags = RAY_FLAG_CULL_BACK_FACING_TRIANGLES;

    #ifdef USE_REFRACTION
        float currentIoR = dot(rayDir, worldNormal) <= 0.0 ? 1 / (refraction*.25+1) : refraction*.25+1;

        float3 n = dot(worldNormal, rayDir) <= 0.0 ? worldNormal : -worldNormal;

        transparentRay.Origin = worldPos;
        transparentRay.Direction = refract(normalize(rayDir), n, currentIoR);
    #else
        transparentRay.Origin = worldPos;
        transparentRay.Direction = normalize(rayDir);
    #endif

    transparentRay.TMin = 0.001;
    transparentRay.TMax = gClipDistance*.75;

    RayPayload transPayload;
    transPayload.color = 0;
    transPayload.randomSeed = rayPayload.randomSeed;
    transPayload.depth = rayPayload.depth + 1;
    transPayload.data = 0;

    TraceRay(_RaytracingAccelerationStructure, flags, RAYTRACING_DEFAULT, 0, 1, 0, transparentRay, transPayload);

    color = float4(lerp(transPayload.color.xyz, color.xyz, alpha), 1);
    reflect = float3(lerp(transPayload.color.xyz, reflect, alpha));
}

half3 RayGlossyEnvironmentReflection(half3 reflectVector, float3 positionWS, half perceptualRoughness, half occlusion, RayPayload rayPayload)
{
    half3 irradiance;

#if !defined(_ENVIRONMENTREFLECTIONS_OFF)
    if(RayShouldReflect(1.h-perceptualRoughness, rayPayload))
    {
        // half3 randomVector = half3(nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed), nextRand(rayPayload.randomSeed)) * 2.h - 1.h;
        //
        // float3 scatterRayDir = normalize(reflectVector+(randomVector * perceptualRoughness));

        half3 reflection = RayReflectionCalc(positionWS, reflectVector, rayPayload);
        if (reflection.x > 0.f)
        {
            return reflection;
        }
    }
    if (_REFLECTION_PROBE_BLENDING)
    {
        irradiance = CalculateIrradianceFromReflectionProbes(reflectVector, positionWS, perceptualRoughness, half2(1.f, 1.f));
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
            reflectVector = BoxProjectedCubemapDirection(reflectVector, positionWS, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
            #endif
        }
        half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
        half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip));

        irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
    }
#else // _ENVIRONMENTREFLECTIONS_OFF
    irradiance = _GlossyEnvironmentColor.rgb;
#endif // !_ENVIRONMENTREFLECTIONS_OFF

    return irradiance * occlusion;
}

half3 RayGlobalIllumination(BRDFData brdfData, BRDFData brdfDataClearCoat, float clearCoatMask,
    half3 bakedGI, half occlusion, float3 positionWS,
    half3 normalWS, half3 viewDirectionWS, RayPayload rayPayload)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NoV = saturate(dot(normalWS, viewDirectionWS));
    half fresnelTerm = Pow4(1.0 - NoV);

    half3 indirectDiffuse = bakedGI;
    half3 indirectSpecular = RayGlossyEnvironmentReflection(reflectVector, positionWS, brdfData.perceptualRoughness, 1.0h, rayPayload);

    half3 color = EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);

    if (IsOnlyAOLightingFeatureEnabled())
    {
        color = half3(1,1,1); // "Base white" for AO debug lighting mode
    }

    #if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
    half3 coatIndirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfDataClearCoat.perceptualRoughness, 1.0h, normalizedScreenSpaceUV);
    // TODO: "grazing term" causes problems on full roughness
    half3 coatColor = EnvironmentBRDFClearCoat(brdfDataClearCoat, clearCoatMask, coatIndirectSpecular, fresnelTerm);

    // Blend with base layer using khronos glTF recommended way using NoV
    // Smooth surface & "ambiguous" lighting
    // NOTE: fresnelTerm (above) is pow4 instead of pow5, but should be ok as blend weight.
    half coatFresnel = kDielectricSpec.x + kDielectricSpec.a * fresnelTerm;
    return (color * (1.0 - coatFresnel * clearCoatMask) + coatColor) * occlusion;
    #else
    return color * occlusion;
    #endif
}

half4 RayUniversalFragmentPBR(InputData inputData, SurfaceData surfaceData, RayPayload rayPayload)
{
    #if defined(_SPECULARHIGHLIGHTS_OFF)
    bool specularHighlightsOff = true;
    #else
    bool specularHighlightsOff = false;
    #endif
    BRDFData brdfData;


    // NOTE: can modify "surfaceData"...
    InitializeBRDFData(surfaceData, brdfData);

    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
    {
        return debugColor;
    }
    #endif

    // Clear-coat calculation...
    BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
    half4 shadowMask = half4(1, 1, 1, 1); //CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    uint meshRenderingLayers = GetMeshRenderingLayer();
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    // NOTE: We don't apply AO to the GI here because it's done in the lighting calculation below...
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

    LightingData lightingData = CreateLightingData(inputData, surfaceData);

#ifdef _PLASTIC_LIGHTING_SETUP
    half3 reflectVector = reflect(-inputData.viewDirectionWS, inputData.normalWS);
    half3 reflection = RayGlossyEnvironmentReflection(reflectVector, inputData.positionWS,
                                          1.0 - surfaceData.smoothness, 1.0h, rayPayload);

    half reflectance = saturate(pow(surfaceData.smoothness, 6));

    half NoV = saturate(dot(inputData.normalWS, inputData.viewDirectionWS));
    half fresnelTerm = Pow4(1.0 - NoV);

    surfaceData.specular = brdfData.specular;
    half3 specularReflection = reflection * brdfData.specular;

    float3 diffuseGI = inputData.bakedGI * brdfData.diffuse;
    lightingData.giColor = (lerp(diffuseGI, specularReflection, reflectance)) * aoFactor.indirectAmbientOcclusion;
    lightingData.giColor += (surfaceData.metallic * reflectance * fresnelTerm) * brdfData.specular;
#else
    lightingData.giColor = RayGlobalIllumination(brdfData, brdfDataClearCoat, surfaceData.clearCoatMask,
                                              inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS,
                                              inputData.normalWS, inputData.viewDirectionWS, rayPayload);
#endif

#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
    #ifdef _PLASTIC_LIGHTING_SETUP
        lightingData.mainLightColor += CalculatePlasticBlinnPhong(mainLight, inputData, surfaceData);
    #else
        lightingData.mainLightColor = LightingPhysicallyBased(brdfData, brdfDataClearCoat,
                                                              mainLight,
                                                              inputData.normalWS, inputData.viewDirectionWS,
                                                              surfaceData.clearCoatMask, specularHighlightsOff);
    #endif
    }

    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_CLUSTER_LIGHT_LOOP
    [loop] for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        CLUSTER_LIGHT_LOOP_SUBTRACTIVE_LIGHT_CHECK

        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
        #ifdef _PLASTIC_LIGHTING_SETUP
            lightingData.additionalLightsColor += CalculatePlasticBlinnPhong(light, inputData, surfaceData);
        #else
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        #endif
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
        #ifdef _PLASTIC_LIGHTING_SETUP
            lightingData.additionalLightsColor += CalculatePlasticBlinnPhong(light, inputData, surfaceData);
        #else
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                          inputData.normalWS, inputData.viewDirectionWS,
                                                                          surfaceData.clearCoatMask, specularHighlightsOff);
        #endif
        }
    LIGHT_LOOP_END
    #endif

    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * brdfData.diffuse;
    #endif

#if REAL_IS_HALF
    // Clamp any half.inf+ to HALF_MAX
    return min(CalculateFinalColor(lightingData, surfaceData.alpha), HALF_MAX);
#else
    return CalculateFinalColor(lightingData, surfaceData.alpha);
#endif
}
#endif
