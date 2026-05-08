#ifndef PLASTIC_LIGHTING_INCLUDED
#define PLASTIC_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"

half PlasticSubsurface(half3 lightDir, half3 normal)
{
    half DotL = dot(lightDir, normal);
    return pow(1.0 - abs(DotL), 4);
}

half3 PlasticLambert(half3 lightColor, half3 lightDir, half3 normal)
{
    half NdotL = saturate(dot(normal, lightDir));
    return lightColor * NdotL;
}

half3 LightingPlasticSpecular(half3 lightColor, half3 lightDir, half3 normal, half3 viewDir, half4 specular, half specularFactor, half smoothness)
{
    float3 halfVec = SafeNormalize(float3(lightDir) + float3(viewDir));
    half NdotH = half(saturate(dot(normal, halfVec)));
    half modifier = pow(float(NdotH), float(specularFactor))*float(smoothness);
    float3 specularReflection = specular.rgb * modifier;
    return lightColor * specularReflection;
}

half3 CalculatePlasticBlinnPhong(Light light, InputData inputData, SurfaceData surfaceData)
{
    half3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    half3 lightDiffuseColor = PlasticLambert(attenuatedLightColor, light.direction, inputData.normalWS);
    half3 lightSpecularColor = half3(0,0,0);

#if defined(_SPECGLOSSMAP) || defined(_SPECULAR_COLOR) || !defined(_SPECULARHIGHLIGHTS_OFF)
    half specularFactor = 60;
    #ifdef _HAS_SPECULAR_FACTOR
    specularFactor = surfaceData.extraProp;
    #endif

    lightSpecularColor += LightingPlasticSpecular(attenuatedLightColor, light.direction, inputData.normalWS, inputData.viewDirectionWS, half4(surfaceData.specular, 1), specularFactor, surfaceData.smoothness);
#endif

#if defined(_SUBSURFACECOLOR) || defined(_SUBSURFACEMAP)
    half lightSubsurfaceStrength = (PlasticSubsurface(light.direction, inputData.normalWS)) * surfaceData.subsurfaceScale * saturate(Luminance(attenuatedLightColor));
    half3 albedo = lerp(surfaceData.albedo, surfaceData.subsurfaceColor, lightSubsurfaceStrength);
#else
    half3 albedo = surfaceData.albedo;
#endif
    #if _ALPHAPREMULTIPLY_ON
    return lightDiffuseColor * albedo * surfaceData.alpha + lightSpecularColor;
    #else
    return lightDiffuseColor * albedo + lightSpecularColor;
    #endif
}

#endif
