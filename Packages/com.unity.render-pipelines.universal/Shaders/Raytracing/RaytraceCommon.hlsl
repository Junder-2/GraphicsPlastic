#ifndef RAYTRACING_COMMON_INCLUDED
#define RAYTRACING_COMMON_INCLUDED

#include "UnityRaytracingMeshUtils.cginc"

#ifndef SHADER_STAGE_COMPUTE
// raytracing scene
RaytracingAccelerationStructure  _RaytracingAccelerationStructure;
#endif

#define RAYTRACING_DEFAULT (1 << 0)
#define RAYTRACING_SHADOW (1 << 1)
#define SHADOWRAY_FLAG 0x200

#define EPSILON         1.0e-4

// max recursion depth
static const uint gMaxDepth = 3;

static const float gShadowOffset = .05f;

static const float LODbias = 1.f;

uniform int gClipDistance;
uniform int gMaxReflectDepth;
uniform float gLODBias;

half4 RaySampleTex2DLod(Texture2D tex, SamplerState sampler, float2 uv, float lod)
{
    return tex.SampleLevel(sampler, uv, lod + gLODBias);
}

half4 RaySampleTex2D(Texture2D tex, SamplerState sampler, float2 uv, float lod)
{
    float pixelHeight = 0, pixelWidth = 0;
    tex.GetDimensions(pixelWidth, pixelHeight);
    lod += log2(pixelWidth*pixelHeight)*.5;
    lod += gLODBias;

    return tex.SampleLevel(sampler, uv, lod);
}

float RayCalcLOD(float triangleArea, float texCoordArea, float coneWidth, float3 rayDir, float3 normal)
{
    float lambda = log2(texCoordArea/triangleArea)*.5;
    lambda += log2(abs(coneWidth));
    lambda -= log2(abs(dot(rayDir, normal)));

    return lambda-1.f;
}

float RayCalcLOD(float coneWidth, float3 rayDir, float3 normal)
{
    float lambda = log2(abs(coneWidth));
    lambda -= log2(abs(dot(rayDir, normal)));

    return lambda-1.f;
}

half RayAlphaClip(half alpha, half cutoff)
{
    bool zeroCutoff = (cutoff <= 0.0);

    return !zeroCutoff ? step(cutoff, alpha) : alpha;
}

// compute random seed from one input
// http://reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
uint initRand(uint seed)
{
	seed = (seed ^ 61) ^ (seed >> 16);
	seed *= 9;
	seed = seed ^ (seed >> 4);
	seed *= 0x27d4eb2d;
	seed = seed ^ (seed >> 15);

	return seed;
}

// compute random seed from two inputs
// https://github.com/nvpro-samples/optix_prime_baking/blob/master/random.h
uint initRand(uint seed1, uint seed2)
{
	uint seed = 0;

	[unroll]
	for(uint i = 0; i < 16; i++)
	{
		seed += 0x9e3779b9;
		seed1 += ((seed2 << 4) + 0xa341316c) ^ (seed2 + seed) ^ ((seed2 >> 5) + 0xc8013ea4);
		seed2 += ((seed1 << 4) + 0xad90777d) ^ (seed1 + seed) ^ ((seed1 >> 5) + 0x7e95761e);
	}

	return seed1;
}

// next random number
// http://reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
float nextRand(inout uint seed)
{
	seed = 1664525u * seed + 1013904223u;
	return float(seed & 0x00FFFFFF) / float(0x01000000);
}

// ray payload
struct RayPayload
{
	// Color of the ray
	half3 color;
	half shadow;
	// Random Seed
	uint randomSeed;
	// Recursion depth
	uint depth;
	uint data;

	float rayConeWidth;
	float rayConeSpreadAngle;
};

struct ShadowHitInfo
{
	bool isHit;
};

// Triangle attributes
struct AttributeData
{
	// Barycentric value of the intersection
	float2 barycentrics;
};

// Macro that interpolate any attribute using barycentric coordinates
#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)

bool ShadowRay(float3 origin, half3 direction, float Tmin, float Tmax)
{
	RayDesc shadowRay;
    shadowRay.Origin = origin;
    shadowRay.Direction = direction;
    shadowRay.TMin = Tmin;
    shadowRay.TMax = Tmax;

	ShadowHitInfo shadowPayload;
    shadowPayload.isHit = true;

	uint flags = RAY_FLAG_FORCE_NON_OPAQUE | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER | SHADOWRAY_FLAG;

    TraceRay(_RaytracingAccelerationStructure, flags, RAYTRACING_SHADOW, 0, 0, 1, shadowRay, shadowPayload);
    return (shadowPayload.isHit);
}

#endif // RAYTRACING_COMMON_INCLUDED
