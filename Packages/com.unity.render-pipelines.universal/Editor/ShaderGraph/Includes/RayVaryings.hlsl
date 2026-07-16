// Structure to fill for intersections
struct IntersectionVertex
{
	// Object space position of the vertex
	float3 positionOS;
#ifdef VARYINGS_NEED_NORMAL_WS
	// Object space normal of the vertex
	float3 normalOS;
#endif
#ifdef VARYINGS_NEED_TANGENT_WS
	// Object space normal of the vertex
	float3 tangentOS;
#endif
	// UV coordinates
#ifdef VARYINGS_NEED_TEXCOORD0
	float2 texCoord0;
#endif
#ifdef VARYINGS_NEED_TEXCOORD1
	float2 texCoord1;
#endif
#ifdef VARYINGS_NEED_TEXCOORD2
	float2 texCoord2;
#endif
#ifdef VARYINGS_NEED_TEXCOORD3
	float2 texCoord3;
#endif
#ifdef VARYINGS_NEED_TEXCOORD4
	float2 texCoord4;
#endif
#ifdef VARYINGS_NEED_TEXCOORD5
	float2 texCoord5;
#endif
#ifdef VARYINGS_NEED_TEXCOORD6
	float2 texCoord6;
#endif
#ifdef VARYINGS_NEED_TEXCOORD7
	float2 texCoord7;
#endif
#ifdef VARYINGS_NEED_COLOR
	// Vertex color
	float4 color;
#endif
	// Value used for LOD sampling
	float  triangleArea;
#ifdef VARYINGS_NEED_TEXCOORD0
	float  texCoord0Area;
#endif
// #ifdef VARYINGS_NEED_TEXCOORD1
// 	float  texCoord1Area;
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD2
// 	float  texCoord2Area;
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD3
// 	float  texCoord3Area;
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD4
//     float  texCoord4Area;
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD5
//     float  texCoord5Area;
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD6
//     float  texCoord6Area;
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD7
//     float  texCoord7Area;
// #endif

	bool frontFace;
};

// Fetch the intersetion vertex data for the target vertex
void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
{
	outVertex.positionOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
#ifdef VARYINGS_NEED_NORMAL_WS
	outVertex.normalOS   = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
#endif
#ifdef VARYINGS_NEED_TANGENT_WS
	outVertex.tangentOS  = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeTangent);
#endif
#ifdef VARYINGS_NEED_COLOR
	outVertex.color      = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeColor);
#endif
#ifdef VARYINGS_NEED_TEXCOORD0
	outVertex.texCoord0  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
#endif
#ifdef VARYINGS_NEED_TEXCOORD1
	outVertex.texCoord1  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord1);
#endif
#ifdef VARYINGS_NEED_TEXCOORD2
	outVertex.texCoord2  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord2);
#endif
#ifdef VARYINGS_NEED_TEXCOORD3
	outVertex.texCoord3  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord3);
#endif
#ifdef VARYINGS_NEED_TEXCOORD4
    outVertex.texCoord4  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord4);
#endif
#ifdef VARYINGS_NEED_TEXCOORD5
    outVertex.texCoord5  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord5);
#endif
#ifdef VARYINGS_NEED_TEXCOORD6
    outVertex.texCoord6  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord6);
#endif
#ifdef VARYINGS_NEED_TEXCOORD7
    outVertex.texCoord7  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord7);
#endif
}

void GetCurrentIntersectionVertex(AttributeData attributeData, out IntersectionVertex outVertex, float3 viewDir = 0)
{
	// Fetch the indices of the currentr triangle
	uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

	// Fetch the 3 vertices
	IntersectionVertex v0, v1, v2;
	FetchIntersectionVertex(triangleIndices.x, v0);
	FetchIntersectionVertex(triangleIndices.y, v1);
	FetchIntersectionVertex(triangleIndices.z, v2);

    float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
    v0.positionOS = mul(objectToWorld, v0.positionOS);
    v1.positionOS = mul(objectToWorld, v1.positionOS);
    v2.positionOS = mul(objectToWorld, v2.positionOS);
    float3 vertexCross = cross(v1.positionOS - v0.positionOS, v2.positionOS - v0.positionOS);

    outVertex.frontFace = dot(viewDir, normalize(vertexCross)) < 0;

	// Compute the full barycentric coordinates
	float3 barycentricCoordinates = float3(1.0 - attributeData.barycentrics.x - attributeData.barycentrics.y, attributeData.barycentrics.x, attributeData.barycentrics.y);

	// Interpolate all the data
#ifdef VARYINGS_NEED_POSITION_WS
	outVertex.positionOS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.positionOS, v1.positionOS, v2.positionOS, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_NORMAL_WS
	outVertex.normalOS   = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normalOS, v1.normalOS, v2.normalOS, barycentricCoordinates) * (outVertex.frontFace ? 1.0 : -1.0);
#endif
#ifdef VARYINGS_NEED_TANGENT_WS
	outVertex.tangentOS  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.tangentOS, v1.tangentOS, v2.tangentOS, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_COLOR
	outVertex.color      = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.color, v1.color, v2.color, barycentricCoordinates);

    if (!any(outVertex.color))
        outVertex.color = 1.0;

#endif
#ifdef VARYINGS_NEED_TEXCOORD0
	outVertex.texCoord0  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_TEXCOORD1
	outVertex.texCoord1  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord1, v1.texCoord1, v2.texCoord1, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_TEXCOORD2
	outVertex.texCoord2  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord2, v1.texCoord2, v2.texCoord2, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_TEXCOORD3
	outVertex.texCoord3  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord3, v1.texCoord3, v2.texCoord3, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_TEXCOORD4
    outVertex.texCoord4  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord4, v1.texCoord4, v2.texCoord4, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_TEXCOORD5
    outVertex.texCoord5  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord5, v1.texCoord5, v2.texCoord5, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_TEXCOORD6
    outVertex.texCoord6  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord6, v1.texCoord6, v2.texCoord6, barycentricCoordinates);
#endif
#ifdef VARYINGS_NEED_TEXCOORD7
    outVertex.texCoord7  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord7, v1.texCoord7, v2.texCoord7, barycentricCoordinates);
#endif

	// Compute the lambda value (area computed in object space)
	outVertex.triangleArea  = length(vertexCross);
#ifdef VARYINGS_NEED_TEXCOORD0
	outVertex.texCoord0Area = abs((v1.texCoord0.x - v0.texCoord0.x) * (v2.texCoord0.y - v0.texCoord0.y) - (v2.texCoord0.x - v0.texCoord0.x) * (v1.texCoord0.y - v0.texCoord0.y));
#endif
// #ifdef VARYINGS_NEED_TEXCOORD1
// 	outVertex.texCoord1Area = abs((v1.texCoord1.x - v0.texCoord1.x) * (v2.texCoord1.y - v0.texCoord1.y) - (v2.texCoord1.x - v0.texCoord1.x) * (v1.texCoord1.y - v0.texCoord1.y));
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD2
// 	outVertex.texCoord2Area = abs((v1.texCoord2.x - v0.texCoord2.x) * (v2.texCoord2.y - v0.texCoord2.y) - (v2.texCoord2.x - v0.texCoord2.x) * (v1.texCoord2.y - v0.texCoord2.y));
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD3
// 	outVertex.texCoord3Area = abs((v1.texCoord3.x - v0.texCoord3.x) * (v2.texCoord3.y - v0.texCoord3.y) - (v2.texCoord3.x - v0.texCoord3.x) * (v1.texCoord3.y - v0.texCoord3.y));
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD4
//     outVertex.texCoord4Area = abs((v1.texCoord4.x - v0.texCoord4.x) * (v2.texCoord4.y - v0.texCoord4.y) - (v2.texCoord4.x - v0.texCoord4.x) * (v1.texCoord4.y - v0.texCoord4.y));
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD5
//     outVertex.texCoord5Area = abs((v1.texCoord5.x - v0.texCoord5.x) * (v2.texCoord5.y - v0.texCoord5.y) - (v2.texCoord5.x - v0.texCoord5.x) * (v1.texCoord5.y - v0.texCoord5.y));
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD6
//     outVertex.texCoord6Area = abs((v1.texCoord6.x - v0.texCoord6.x) * (v2.texCoord6.y - v0.texCoord6.y) - (v2.texCoord6.x - v0.texCoord6.x) * (v1.texCoord6.y - v0.texCoord6.y));
// #endif
// #ifdef VARYINGS_NEED_TEXCOORD7
//     outVertex.texCoord7Area = abs((v1.texCoord7.x - v0.texCoord7.x) * (v2.texCoord7.y - v0.texCoord7.y) - (v2.texCoord7.x - v0.texCoord7.x) * (v1.texCoord7.y - v0.texCoord7.y));
// #endif
}

#if defined(HAVE_VFX_MODIFICATION)
bool PrepareVFXModification(inout Attributes input, inout Varyings output, inout AttributesElement element)
{
    if (!GetMeshAndElementIndex(input, element))
        return true; // Culled index.

#if UNITY_ANY_INSTANCING_ENABLED
    output.instanceID = input.instanceID; //Transfer instanceID again because we modify it in GetMeshAndElementIndex
#endif

    if (!GetInterpolatorAndElementData(input, output, element))
        return true; // Dead particle.

    SetupVFXMatrices(element, output);

    return false;
}
#endif

Varyings BuildVaryings(RayPayload rayPayload, AttributeData attributeData, out bool outFrontFace)
{
    float3 rayOrigin = WorldRayOrigin();
    float3 rayDir = WorldRayDirection();
    float3 positionWS = rayOrigin + RayTCurrent() * rayDir;
    // compute vertex data on ray/triangle intersection
    IntersectionVertex currentvertex;
    GetCurrentIntersectionVertex(attributeData, currentvertex, rayDir);

    outFrontFace = currentvertex.frontFace;

    Varyings output = (Varyings)0;

    bool isCulledOrDead = false;

#if defined(HAVE_VFX_MODIFICATION)
    AttributesElement element;
    ZERO_INITIALIZE(AttributesElement, element);

    isCulledOrDead = PrepareVFXModification(input, output, element);
#endif

    if (!isCulledOrDead)
    {
        #ifdef UNIVERSAL_TERRAIN_ENABLED
        TerrainVaryingGeneration(input, output);
        #endif

    #ifdef ATTRIBUTES_NEED_NORMAL
        float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
        float3 normalWS = normalize(mul(objectToWorld, currentvertex.normalOS));
    #else
        // Required to compile ApplyVertexModification that doesn't use normal.
        float3 normalWS = float3(0.0, 0.0, 0.0);
    #endif
    #ifdef UNIVERSAL_TERRAIN_ENABLED
        #if defined(_NORMALMAP) && !defined(ENABLE_TERRAIN_PERPIXEL_NORMAL)
            half3 viewDirWS = normalize(-rayDir);
            float4 vertexTangent = float4(cross(float3(0.0, 0.0, 1.0), currentvertex.normalOS), 1.0);
            VertexNormalInputs normalInput = GetVertexNormalInputs(currentvertex.normalOS, vertexTangent);

            output.normalViewDir = float4(normalInput.normalWS, viewDirWS.x);
            output.tangentViewDir = float4(normalInput.tangentWS, viewDirWS.y);
            output.bitangentViewDir = float4(normalInput.bitangentWS, viewDirWS.z);

            float4 tangentWS = float4(normalInput.tangentWS, 1.0);
        #else
            float4 tangentWS = float4(1.0, 0.0, 0.0, 0.0);
        #endif
    #else
        #ifdef ATTRIBUTES_NEED_TANGENT
            float4 tangentWS = float4(TransformObjectToWorldDir(currentvertex.tangentOS.xyz), 1.0);
        #endif
    #endif
        // TODO: Change to inline ifdef
        // Do vertex modification in camera relative space (if enabled)
    #if defined(HAVE_VERTEX_MODIFICATION)
        ApplyVertexModification(input, normalWS, positionWS, _TimeParameters.xyz);
    #endif

    #ifdef VARYINGS_NEED_POSITION_WS
        output.positionWS = positionWS;
    #endif

    #ifdef VARYINGS_NEED_NORMAL_WS
        output.normalWS = normalWS;         // normalized in TransformObjectToWorldNormal()
    #endif

    #ifdef VARYINGS_NEED_TANGENT_WS
        output.tangentWS = tangentWS;       // normalized in TransformObjectToWorldDir()
    #endif

    // output.positionCS = TransformWorldToHClip(positionWS);
    float2 screenPos = (float2)DispatchRaysIndex().xy/(float2)DispatchRaysDimensions().xy;
    output.positionCS = float4(screenPos * _ScaledScreenParams.xy, 1.0, 1.0);

    #if defined(VARYINGS_NEED_TEXCOORD0) || defined(VARYINGS_DS_NEED_TEXCOORD0)
        output.texCoord0 = currentvertex.texCoord0.xyxy;
        output.rayLod = RayCalcLOD(currentvertex.triangleArea, currentvertex.texCoord0Area, rayPayload.rayConeWidth, rayDir, normalWS);
    #else
        output.rayLod = RayCalcLOD(currentvertex.triangleArea, 1.0, rayPayload.rayConeWidth, rayDir, normalWS);
    #endif
    #ifdef EDITOR_VISUALIZATION
        float2 VizUV = 0;
        float4 LightCoord = 0;
        UnityEditorVizData(currentvertex.positionOS, currentvertex.texCoord0, currentvertex.texCoord1, currentvertex.texCoord2, VizUV, LightCoord);
    #endif
    #if defined(VARYINGS_NEED_TEXCOORD1) || defined(VARYINGS_DS_NEED_TEXCOORD1)
    #ifdef EDITOR_VISUALIZATION
        output.texCoord1 = float4(VizUV, 0, 0);
    #else
        output.texCoord1 = currentvertex.texCoord1.xyxy;
    #endif
    #endif
    #if defined(VARYINGS_NEED_TEXCOORD2) || defined(VARYINGS_DS_NEED_TEXCOORD2)
    #ifdef EDITOR_VISUALIZATION
        output.texCoord2 = LightCoord;
    #else
        output.texCoord2 = currentvertex.texCoord2.xyxy;
    #endif
    #endif
    #if defined(VARYINGS_NEED_TEXCOORD3) || defined(VARYINGS_DS_NEED_TEXCOORD3)
        output.texCoord3 = currentvertex.texCoord3.xyxy;
    #endif

    #if defined(VARYINGS_NEED_TEXCOORD4) || defined(VARYINGS_DS_NEED_TEXCOORD4)
        output.texCoord4 = currentvertex.texCoord4.xyxy;
    #endif

    #if defined(VARYINGS_NEED_TEXCOORD5) || defined(VARYINGS_DS_NEED_TEXCOORD5)
        output.texCoord5 = currentvertex.texCoord5.xyxy;
    #endif

    #if defined(VARYINGS_NEED_TEXCOORD6) || defined(VARYINGS_DS_NEED_TEXCOORD6)
        output.texCoord6 = currentvertex.texCoord6.xyxy;
    #endif

    #if defined(VARYINGS_NEED_TEXCOORD7) || defined(VARYINGS_DS_NEED_TEXCOORD7)
        output.texCoord7 = currentvertex.texCoord7.xyxy;
    #endif

    #if defined(VARYINGS_NEED_COLOR) || defined(VARYINGS_DS_NEED_COLOR)
        output.color = currentvertex.color;
    #endif

    #if (defined(VARYINGS_NEED_INSTANCEID) || defined(VARYINGS_DS_NEED_INSTANCEID)) && !UNITY_ANY_INSTANCING_ENABLED
        // output.instanceID = input.instanceID;
    #endif

    #ifdef VARYINGS_NEED_SCREENPOSITION
        output.screenPosition = screenPos;
    #endif
    #ifdef UNIVERSAL_TERRAIN_ENABLED
        #if (SHADERPASS == SHADERPASS_FORWARD) || (SHADERPASS == SHADERPASS_GBUFFER)
            OUTPUT_LIGHTMAP_UV(currentvertex.texCoord0, unity_LightmapST, output.staticLightmapUV);
        #if defined(DYNAMICLIGHTMAP_ON)
            output.dynamicLightmapUV.xy = currentvertex.texCoord0.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
        #endif
            OUTPUT_SH4(positionWS, normalWS.xyz, GetWorldSpaceNormalizeViewDir(positionWS), output.sh, output.probeOcclusion);
        #endif
    #else
        #if (SHADERPASS == SHADERPASS_FORWARD) || (SHADERPASS == SHADERPASS_GBUFFER)
            OUTPUT_LIGHTMAP_UV(currentvertex.texCoord0, unity_LightmapST, output.staticLightmapUV);
        #if defined(DYNAMICLIGHTMAP_ON)
            output.dynamicLightmapUV.xy = currentvertex.texCoord2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
        #endif
            OUTPUT_SH4(positionWS, normalWS.xyz, GetWorldSpaceNormalizeViewDir(positionWS), output.sh, output.probeOcclusion);
        #endif
    #endif
    #ifdef VARYINGS_NEED_FOG_AND_VERTEX_LIGHT
        half fogFactor = 0;
    #if !defined(_FOG_FRAGMENT)
            fogFactor = ComputeFogFactor(output.positionCS.z);
    #endif
        half3 vertexLight = VertexLighting(positionWS, normalWS);
        output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
    #endif

    #if defined(VARYINGS_NEED_SHADOW_COORD) && defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        output.shadowCoord = TransformWorldToShadowCoord(positionWS);
    #endif

    #if defined(VARYINGS_NEED_SIX_WAY_DIFFUSE_GI_DATA)
        GatherDiffuseGIData(positionWS, normalWS.xyz, tangentWS, output.diffuseGIData0, output.diffuseGIData1, output.diffuseGIData2);
    #endif

        // output.rayLod = RayCalcLOD(rayPayload.rayConeWidth, rayDir, normalWS);
    }

    return output;
}

SurfaceDescription BuildSurfaceDescription(Varyings varyings)
{
    SurfaceDescriptionInputs surfaceDescriptionInputs = BuildSurfaceDescriptionInputs(varyings);
#if defined(HAVE_VFX_MODIFICATION)
    GraphProperties properties;
    ZERO_INITIALIZE(GraphProperties, properties);
    GetElementPixelProperties(surfaceDescriptionInputs, properties);
    SurfaceDescription surfaceDescription = SurfaceDescriptionFunction(surfaceDescriptionInputs, properties);
#else
    SurfaceDescription surfaceDescription = SurfaceDescriptionFunction(surfaceDescriptionInputs);
#endif
    return surfaceDescription;
}
