#include "Packages/com.unity.render-pipelines.universal/Shaders/Raytracing/RaytracingHelpers.hlsl"

#if defined(USE_RAYLOD)
#undef SAMPLE_TEXTURE2D
#define SAMPLE_TEXTURE2D(textureName, samplerName, coord2) RaySampleTex2D(textureName, samplerName, coord2, RayLod);
#undef SAMPLE_TEXTURE2D_BIAS
#define SAMPLE_TEXTURE2D_BIAS(textureName, samplerName, coord2, bias) RaySampleTex2DLod(textureName, samplerName, coord2, RayLod + bias);
#else
#undef SAMPLE_TEXTURE2D
#define SAMPLE_TEXTURE2D(textureName, samplerName, coord2) RaySampleTex2DLod(textureName, samplerName, coord2, 0)
#undef SAMPLE_TEXTURE2D_BIAS
#define SAMPLE_TEXTURE2D_BIAS(textureName, samplerName, coord2, bias) RaySampleTex2DLod(textureName, samplerName, coord2, bias)
#endif
