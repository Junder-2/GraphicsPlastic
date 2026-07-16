using System;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace UnityEngine.Rendering.Universal
{
    using RenderMode = RaytracingSettings.RenderMode;
    using BlurMode = RaytracingSettings.BlurMode;
    using SamplingMode = RaytracingSettings.SamplingMode;

    internal class RaytracingPass : ScriptableRenderPass
    {
        private int m_FrameIndex;
        private float m_CullUpdate = 0f;
        private int m_PrevTargetFrameRate = 0;
        private float m_UpdateTarget = 0f;
        private float m_CaptureUpdate = 0f;

        private bool m_Rendered;

        private RTHandle m_ReflectionTargetHandle;
        // private RTHandle shadowTarget;
        private RayTracingShader m_RayTracingShader;
        private RaytracingSettings m_CurrentSettings;

        // Targets
        private string[] m_BlurMipDownName;
        private string[] m_BlurMipUpName;
        private TextureHandle[] m_BlurMipUp;
        private TextureHandle[] m_BlurMipDown;
        private Material m_BlurMat;

        private RayTracingAccelerationStructure m_AccelerationStructure;

        //private Raytracing raytracingVolume;
        private RayTracingInstanceCullingConfig m_RaytracingCullingConfig;

        private static readonly int id_AccelerationStructure = Shader.PropertyToID("_RaytracingAccelerationStructure");

        private static readonly int id_MaxReflectDepth = Shader.PropertyToID("gMaxReflectDepth");
        private static readonly int id_ClipDistance = Shader.PropertyToID("gClipDistance");
        private static readonly int id_LODBias = Shader.PropertyToID("gLODBias");

        private static readonly int id_NearClip = Shader.PropertyToID("_NearClip");
        private static readonly int id_PixelSpreadAngle = Shader.PropertyToID("_PixelSpreadAngle");
        private static readonly int id_CameraToWorld = Shader.PropertyToID("_CameraToWorld");
        private static readonly int id_CameraInverseProjection = Shader.PropertyToID("_CameraInverseProjection");
        private static readonly int id_ReflectionRenderTarget = Shader.PropertyToID("_ReflectionRenderTarget");
        private static readonly int id_ShadowRenderTarget = Shader.PropertyToID("_ShadowRenderTarget");
        private static readonly int id_WriteReflections = Shader.PropertyToID("_WriteReflections");
        private static readonly int id_WriteShadows = Shader.PropertyToID("_WriteShadows");
        private static readonly int id_FrameIndex = Shader.PropertyToID("_FrameIndex");

        private static readonly int id_ScreenSpaceReflectionTexture = Shader.PropertyToID("_ScreenSpaceReflectionTexture");

        private static readonly int id_AccumulateReflection = Shader.PropertyToID("_AccumulateReflection");
        private static readonly int id_BlendOffsetId = Shader.PropertyToID("_AccumulateReflectionOffset");
        private static readonly int id_AccumulateFrameIndex = Shader.PropertyToID("_AccumulateReflectionFrameIndex");

        private const int MaxMipBlurCount = 8;

        internal RaytracingPass()
        {
            m_CurrentSettings = new RaytracingSettings();
            m_RayParamsPrev = new ShaderParams(true);
            m_TexParamsPrev = new TextureParams(true);
            m_AccumulateMaterialParamsPrev = new AccumulateMaterialParams(true);
            m_FrameIndex = 0;

            // Arrays for Bloom pyramid TextureHandle names.
            m_BlurMipDownName = new string[MaxMipBlurCount];
            m_BlurMipUpName = new string[MaxMipBlurCount];

            for (int i = 0; i < MaxMipBlurCount; i++)
            {
                m_BlurMipUpName[i] = "_BlurMipUp" + i;
                m_BlurMipDownName[i] = "_BlurMipDown" + i;
            }

            // Arrays for Bloom pyramid TextureHandles.
            m_BlurMipUp = new TextureHandle[MaxMipBlurCount];
            m_BlurMipDown = new TextureHandle[MaxMipBlurCount];
        }

        internal void ResetParams()
        {
            m_RayParamsPrev = new ShaderParams(true);
            m_TexParamsPrev = new TextureParams(true);
            m_AccumulateMaterialParamsPrev = new AccumulateMaterialParams(true);
            m_FrameIndex = 0;
        }

        internal bool Setup(RaytracingSettings featureSettings, RayTracingShader shader, Material blurMaterial)
        {
            if (shader == null) return false;

            m_CurrentSettings = featureSettings;
            m_RayTracingShader = shader;
            m_BlurMat = blurMaterial;
            ConfigureInput(ScriptableRenderPassInput.Color);
            renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;

            return true;
        }

#if URP_COMPATIBILITY_MODE
        [Obsolete(DeprecationMessage.CompatibilityScriptingAPIObsoleteFrom2023_3)]
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            using (new ProfilingScope(cmd, raySetupProfilingSampler))
            {
                reflectionTarget?.Release();
                shadowTarget?.Release();

                var desc = renderingData.cameraData.cameraTargetDescriptor;
                bool isHDR = renderingData.cameraData.isHdrEnabled;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.enableRandomWrite = true;
                desc.width = (int)(currentSettings.renderScale * desc.width);
                desc.height = (int)(currentSettings.renderScale * desc.height);

                if (currentSettings.raytraceReflections)
                {
                    desc.colorFormat = isHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default;
                    desc.sRGB = false;

                    RenderingUtils.ReAllocateIfNeeded(ref reflectionTarget, desc, FilterMode.Point,
                        TextureWrapMode.Clamp, name: "_RaytraceReflectionTexture");
                    cmd.SetGlobalTexture(reflectionTarget.name, reflectionTarget.nameID);

                    ConfigureTarget(reflectionTarget);
                    ConfigureClear(ClearFlag.None, Color.black);
                }

                if (currentSettings.raytraceShadows)
                {
                    desc.graphicsFormat = RenderingUtils.SupportsGraphicsFormat(GraphicsFormat.R8_UNorm,
                        FormatUsage.Linear | FormatUsage.Render)
                        ? GraphicsFormat.R8_UNorm
                        : GraphicsFormat.B8G8R8A8_UNorm;

                    RenderingUtils.ReAllocateIfNeeded(ref shadowTarget, desc, FilterMode.Point, TextureWrapMode.Clamp,
                        name: "_ScreenSpaceShadowmapTexture");
                    cmd.SetGlobalTexture(shadowTarget.name, shadowTarget.nameID);

                    ConfigureTarget(shadowTarget);
                    ConfigureClear(ClearFlag.None, Color.white);
                }

                UpdateCameraData(cmd, ref renderingData);
                UpdateCulling(ref renderingData);

                cullUpdate += Time.deltaTime;

                if (cullUpdate < 0.033f) return;

                cullUpdate = 0;

                accelerationStructure.ClearInstances();
                accelerationStructure.CullInstances(ref raytracingCullingConfig);
                accelerationStructure.Build();
            }
        }

        private void UpdateCameraData(CommandBuffer cmd, ref RenderingData renderingData)
        {
            ref var cameraData = ref renderingData.cameraData;
            var camera = cameraData.camera;

            float pixelSpreadAngle = Mathf.Atan((2 * Mathf.Tan((Mathf.Deg2Rad * camera.fieldOfView) * .5f))
                                                / camera.scaledPixelHeight);
            cmd.SetRayTracingFloatParam(rayTracingShader, id_PixelSpreadAngle, pixelSpreadAngle);

            cmd.SetRayTracingIntParam(rayTracingShader, id_WriteReflections,
                currentSettings.raytraceReflections ? 1 : 0);
            cmd.SetRayTracingIntParam(rayTracingShader, id_WriteShadows, currentSettings.raytraceShadows ? 1 : 0);

            if (RenderSettings.skybox)
            {
                cmd.SetGlobalTexture(id_Skybox, ReflectionProbe.defaultTexture);
                cmd.SetGlobalVector(id_SkyboxHDR, ReflectionProbe.defaultTextureHDRDecodeValues);
            }

            cmd.SetGlobalInteger(id_ClipDistance, (int)camera.farClipPlane);
            cmd.SetGlobalInteger(id_MaxReflectDepth, currentSettings.maxReflectionDepth);

            CoreUtils.SetKeyword(cmd, "_REFLECTIONS_SHADOWS", currentSettings.renderReflectionsMainShadows);

            cmd.SetRayTracingFloatParam(rayTracingShader, id_NearClip, camera.nearClipPlane);
            cmd.SetRayTracingMatrixParam(rayTracingShader, id_CameraToWorld, camera.cameraToWorldMatrix);
            cmd.SetRayTracingMatrixParam(rayTracingShader, id_CameraInverseProjection, camera.projectionMatrix.inverse);
        }

        private void UpdateCulling(ref RenderingData renderingData)
        {
            ref var cameraData = ref renderingData.cameraData;
            var camera = cameraData.camera;

            raytracingCullingConfig.sphereRadius = camera.farClipPlane * .5f;
            raytracingCullingConfig.sphereCenter = cameraData.worldSpaceCameraPos;
            raytracingCullingConfig.lodParameters.fieldOfView = camera.fieldOfView;
            raytracingCullingConfig.lodParameters.cameraPosition = cameraData.worldSpaceCameraPos;
            raytracingCullingConfig.lodParameters.cameraPixelHeight = camera.pixelHeight;
        }

        [Obsolete(DeprecationMessage.CompatibilityScriptingAPIObsoleteFrom2023_3)]
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (currentSettings.renderScale <= 0) return;
            if (!currentSettings.raytraceReflections && !currentSettings.raytraceShadows) return;

            var cmd = renderingData.commandBuffer;

            using (new ProfilingScope(command, rayExecuteProfilingSampler))
            {
                Render(ref renderingData);
            }

            context.ExecuteCommandBuffer(command);
            command.Clear();
            CommandBufferPool.Release(command);
        }

        private void Render(ref RenderingData renderingData, CommandBuffer cmd)
        {
            ref var cameraData = ref renderingData.cameraData;
            var w = renderingData.cameraData.camera.scaledPixelWidth;
            var h = renderingData.cameraData.camera.scaledPixelHeight;

            cmd.EnableShaderKeyword("_FORWARD_PLUS");

            if (currentSettings.raytraceReflections)
            {
                cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreen, true);

                w = m_ReflectionTargetHandle.referenceSize.x;
                h = m_ReflectionTargetHandle.referenceSize.y;
            }
            else
            {
                cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreen, false);
            }

            if (currentSettings.raytraceShadows)
            {
                cmd.SetKeyword(ShaderGlobalKeywords.MainLightShadows, false);
                cmd.SetKeyword(ShaderGlobalKeywords.MainLightShadowCascades, false);
                cmd.SetKeyword(ShaderGlobalKeywords.MainLightShadowScreen, true);

                w = shadowTarget.referenceSize.x;
                h = shadowTarget.referenceSize.y;
            }

            cmd.SetRayTracingTextureParam(rayTracingShader, id_ReflectionRenderTarget,
                currentSettings.raytraceReflections ? m_ReflectionTargetHandle : shadowTarget);
            cmd.SetRayTracingTextureParam(rayTracingShader, id_ShadowRenderTarget,
                currentSettings.raytraceShadows ? shadowTarget : m_ReflectionTargetHandle);

            cmd.SetRayTracingShaderPass(rayTracingShader, "RaytracingLit");
            cmd.SetRayTracingAccelerationStructure(rayTracingShader, id_AccelerationStructure,
                accelerationStructure);

            cmd.DispatchRays(rayTracingShader, "HybridRaytracer", (uint)w, (uint)h, 1u, cameraData.camera);
        }
#endif

        private class ReflectionPassData
        {
            internal RayTracingShader rayTracingShader;
            internal RayTracingAccelerationStructure accelerationStructure;

            internal TextureHandle reflectionTarget;
            internal TextureHandle shadowTarget;

            internal bool raytraceReflections;
            internal bool raytraceShadows;

            internal int width;
            internal int height;

            internal UniversalCameraData cameraData;
        }

        private class MipPassData
        {
            internal TextureHandle[] mipLevels;
            internal TextureHandle reflectionTarget;
        }

        private class BlurPassData
        {
            internal int mipCount;

            internal Material material;

            internal TextureHandle sourceTexture;

            internal TextureHandle[] blurMipUp;
            internal TextureHandle[] blurMipDown;
        }

        private struct TextureParams
        {
            internal int width;
            internal int height;
            internal SamplingMode samplingMode;

            internal bool isDirty;

            internal TextureParams(bool startDirty)
            {
                width = 0;
                height = 0;
                samplingMode = SamplingMode.Point;
                isDirty = startDirty;
            }

            internal TextureParams(ref RaytracingSettings settings, ref RenderTextureDescriptor desc)
            {
                width = desc.width;
                height = desc.height;
                samplingMode = settings.samplingMode;
                isDirty = true;
            }

            internal bool Equals(ref TextureParams other)
            {
                return width == other.width
                       && height == other.height
                       && samplingMode == other.samplingMode
                    ;
            }
        }
        private TextureParams m_TexParamsPrev = new(true);

        private struct ShaderParams
        {
            internal float farClipPlane;
            internal float fieldOfView;
            internal float renderScale;
            internal int scaledPixelHeight;

            internal float lodBias;
            internal byte maxReflectionDepth;
            internal bool raytraceReflections;
            internal bool raytraceShadows;
            internal bool renderReflectionsMainShadows;

            internal SamplingMode samplingMode;
            internal bool genMipMaps;

            internal bool isDirty;

            internal ShaderParams(bool startDirty)
            {
                farClipPlane = 0;
                fieldOfView = 0;
                scaledPixelHeight = 0;
                renderScale = 1;
                lodBias = 0;
                maxReflectionDepth = 0;
                raytraceReflections = false;
                raytraceShadows = false;
                renderReflectionsMainShadows = false;
                samplingMode = SamplingMode.Point;
                genMipMaps = false;
                isDirty = startDirty;
            }

            internal ShaderParams(ref RaytracingSettings settings, ref UniversalCameraData cameraData)
            {
                var camera = cameraData.camera;
                farClipPlane = camera.farClipPlane;
                fieldOfView = camera.fieldOfView;
                scaledPixelHeight = camera.scaledPixelHeight;
                renderScale = settings.renderScale;

                lodBias = settings.lodBias;
                maxReflectionDepth = settings.maxReflectionDepth;
                raytraceReflections = settings.raytraceReflections;
                raytraceShadows = settings.raytraceShadows;
                renderReflectionsMainShadows = settings.renderReflectionsMainShadows;
                samplingMode = settings.samplingMode;
                genMipMaps = settings.generateReflectionMips;

                isDirty = true;
            }

            internal bool Equals(ref ShaderParams other)
            {
                return Mathf.Approximately(farClipPlane, other.farClipPlane)
                       && Mathf.Approximately(fieldOfView, other.fieldOfView)
                       && Mathf.Approximately(renderScale, other.renderScale)
                       && scaledPixelHeight == other.scaledPixelHeight
                       && Mathf.Approximately(lodBias, other.lodBias)
                       && maxReflectionDepth == other.maxReflectionDepth
                       && raytraceReflections == other.raytraceReflections
                       && raytraceShadows == other.raytraceShadows
                       && renderReflectionsMainShadows == other.renderReflectionsMainShadows
                       && samplingMode == other.samplingMode
                    ;
            }
        }
        private ShaderParams m_RayParamsPrev = new(true);

        // Structs
        private struct AccumulateMaterialParams
        {
            internal RenderMode renderMode;
            internal Vector4 blendSampleOffset;

            internal bool isDirty;

            internal AccumulateMaterialParams(bool startDirty)
            {
                renderMode = RenderMode.FullRes;
                blendSampleOffset = default;
                isDirty = startDirty;
            }

            internal AccumulateMaterialParams(ref RaytracingSettings settings)
            {
                renderMode = settings.renderMode;

                Vector2 offset = Vector2.zero;
                switch (renderMode)
                {
                    case RenderMode.HalfLines:
                        offset.x = 0;
                        offset.y = 1;
                        break;
                    case RenderMode.HalfCheckerboard:
                        offset.x = 1;
                        offset.y = 1;
                        break;
                    case RenderMode.FullRes:
                        offset.x = 0;
                        offset.y = 0;
                        break;
                }

                blendSampleOffset = new Vector4(
                    offset.x,                               // x
                    offset.y,                               // y
                    offset.x != 0 ? 1f / offset.x: 0,       // 1 / x
                    offset.y != 0 ? 1f / offset.y : 0    // 1 / y
                );

                isDirty = true;
            }

            internal bool Equals(ref AccumulateMaterialParams other)
            {
                return renderMode == other.renderMode
                    ;
            }
        }
        private AccumulateMaterialParams m_AccumulateMaterialParamsPrev = new(true);

        private LayerMask m_PrevUpdateLayers = new LayerMask();

        void UpdateAccelerationStructure()
        {
            if (m_AccelerationStructure != null && m_PrevUpdateLayers == m_CurrentSettings.updateLayers)
                return;

            m_AccelerationStructure?.Dispose();
            m_AccelerationStructure = null;

            m_PrevUpdateLayers = m_CurrentSettings.updateLayers;

            var accelerationSettings = new RayTracingAccelerationStructure.Settings
            {
                layerMask = m_CurrentSettings.updateLayers,
                managementMode = RayTracingAccelerationStructure.ManagementMode.Manual,
                rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything
            };
            m_AccelerationStructure = new RayTracingAccelerationStructure(accelerationSettings);

            m_RaytracingCullingConfig = new RayTracingInstanceCullingConfig
            {
                flags = RayTracingInstanceCullingFlags.EnableLODCulling | RayTracingInstanceCullingFlags
                                                                            .EnableSphereCulling
                                                                        | RayTracingInstanceCullingFlags
                                                                            .IgnoreReflectionProbes,
                lodParameters = { isOrthographic = false, orthoSize = 0 },
                subMeshFlagsConfig =
                {
                    opaqueMaterials = RayTracingSubMeshFlags.Enabled | RayTracingSubMeshFlags.ClosestHitOnly,
                    alphaTestedMaterials = RayTracingSubMeshFlags.Enabled,
                    transparentMaterials = RayTracingSubMeshFlags.Enabled
                },
                triangleCullingConfig =
                {
                    frontTriangleCounterClockwise = false,
                    checkDoubleSidedGIMaterial = true,
                    optionalDoubleSidedShaderKeywords = new[] { ShaderKeywordStrings.RenderBack, ShaderKeywordStrings.RenderDouble },
                },
                transparentMaterialConfig =
                {
                    optionalShaderKeywords = new[] { ShaderKeywordStrings._SURFACE_TYPE_TRANSPARENT }
                },
                alphaTestedMaterialConfig = { optionalShaderKeywords = new[] { ShaderKeywordStrings._ALPHATEST_ON } }
            };

            var defaultTest = new RayTracingInstanceCullingTest
            {
                allowOpaqueMaterials = true,
                allowTransparentMaterials = true,
                allowAlphaTestedMaterials = true,
                layerMask = m_CurrentSettings.updateLayers,
                instanceMask = 1,
                shadowCastingModeMask = (1 << (int)ShadowCastingMode.Off) | (1 << (int)ShadowCastingMode.On) |
                                        (1 << (int)ShadowCastingMode.TwoSided),
            };
            var shadowTest = new RayTracingInstanceCullingTest
            {
                allowOpaqueMaterials = true,
                allowTransparentMaterials = true,
                allowAlphaTestedMaterials = true,
                layerMask = m_CurrentSettings.updateLayers,
                instanceMask = 2,
                shadowCastingModeMask = (1 << (int)ShadowCastingMode.On) | (1 << (int)ShadowCastingMode.TwoSided) |
                                        (1 << (int)ShadowCastingMode.ShadowsOnly)
            };

            m_RaytracingCullingConfig.instanceTests = new[] { defaultTest, shadowTest };

            m_CullUpdate = 100;

            m_AccelerationStructure.ClearInstances();
            m_AccelerationStructure.CullInstances(ref m_RaytracingCullingConfig);
            m_AccelerationStructure.Build();
        }

        private void UpdateTextures(RenderGraph renderGraph, UniversalCameraData cameraData)
        {
            var desc = cameraData.cameraTargetDescriptor;

            desc.colorFormat = RenderTextureFormat.Default;
            desc.sRGB = false;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;
            desc.enableRandomWrite = true;
            desc.width = Mathf.Max((int)(m_CurrentSettings.renderScale * desc.width), 1);
            desc.height = Mathf.Max((int)(m_CurrentSettings.renderScale * desc.height), 1);
            desc.useMipMap = m_CurrentSettings.generateReflectionMips;
            desc.autoGenerateMips = false;
            desc.mipCount = 0;

            // ReAllocateHandleIfNeeded causes memory leak lol
            TextureParams matParams = new TextureParams(ref m_CurrentSettings, ref desc);
            bool paramsDirty = !m_TexParamsPrev.Equals(ref matParams);    // Checks if the parameters have changed.
            if (!m_TexParamsPrev.isDirty && !paramsDirty)
                return;

            m_TexParamsPrev = matParams;
            m_TexParamsPrev.isDirty = false;

            m_ReflectionTargetHandle?.Release();
            m_ReflectionTargetHandle = null;

            FilterMode filterMode;
            switch (matParams.samplingMode)
            {
                default:
                case SamplingMode.Point:
                    filterMode = FilterMode.Point;
                    break;
                case SamplingMode.Bilinear:
                case SamplingMode.Bicubic:
                    filterMode = FilterMode.Bilinear;
                    break;
                case SamplingMode.Trilinear:
                    filterMode = FilterMode.Trilinear;
                    break;
            }

            RenderingUtils.ReAllocateHandleIfNeeded(ref m_ReflectionTargetHandle, desc, filterMode, TextureWrapMode.Clamp, name: "_RTReflectionTarget");
        }

        private void UpdateParams(ComputeCommandBuffer cmd, ref RaytracingSettings settings, ref UniversalCameraData cameraData)
        {
            // Setting keywords can be somewhat expensive on low-end platforms.
            // Previous params are cached to avoid setting the same keywords every frame.
            ShaderParams shaderParams = new ShaderParams(ref settings, ref cameraData);
            bool paramsDirty = !m_RayParamsPrev.Equals(ref shaderParams);    // Checks if the parameters have changed.
            if (!m_RayParamsPrev.isDirty && !paramsDirty)
                return;

            m_RayParamsPrev = shaderParams;
            m_RayParamsPrev.isDirty = false;

            var camera = cameraData.camera;
            float pixelSpreadAngle = Mathf.Atan((2 * Mathf.Tan((Mathf.Deg2Rad * camera.fieldOfView) * .5f))
                                                / (shaderParams.scaledPixelHeight * Mathf.Lerp(shaderParams.renderScale, 1.0f, .5f)));
            cmd.SetRayTracingFloatParam(m_RayTracingShader, id_PixelSpreadAngle, pixelSpreadAngle);

            cmd.SetRayTracingIntParam(m_RayTracingShader, id_WriteReflections,
                m_CurrentSettings.raytraceReflections ? 1 : 0);
            cmd.SetRayTracingIntParam(m_RayTracingShader, id_WriteShadows, shaderParams.raytraceShadows ? 1 : 0);

            cmd.SetGlobalInteger(id_ClipDistance, (int)camera.farClipPlane);
            cmd.SetGlobalInteger(id_MaxReflectDepth, shaderParams.maxReflectionDepth);
            cmd.SetGlobalFloat(id_LODBias, shaderParams.lodBias);

            CoreUtils.SetKeyword(cmd, "_REFLECTIONS_SHADOWS", shaderParams.renderReflectionsMainShadows);

            if (shaderParams.raytraceReflections)
            {
                cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreen, true);
            }
            else
            {
                cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreen, false);
            }

            if (shaderParams.genMipMaps)
            {
                cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenMipMaps, true);
            }
            else
            {
                cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenMipMaps, false);
            }

            switch (shaderParams.samplingMode)
            {
                case SamplingMode.Point:
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBilinear, false);
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenTrilinear, false);
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBicubic, false);
                    break;
                case SamplingMode.Bilinear:
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBilinear, true);
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenTrilinear, false);
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBicubic, false);
                    break;
                case SamplingMode.Trilinear:
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenTrilinear, true);
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBilinear, false);
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBicubic, false);
                    break;
                case SamplingMode.Bicubic:
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBicubic, true);
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBilinear, false);
                    cmd.SetKeyword(ShaderGlobalKeywords.ReflectionScreenTrilinear, false);
                    break;
            }

            // if (currentSettings.raytraceShadows)
            // {
            //     cmd.SetKeyword(ShaderGlobalKeywords.MainLightShadows, false);
            //     cmd.SetKeyword(ShaderGlobalKeywords.MainLightShadowCascades, false);
            //     cmd.SetKeyword(ShaderGlobalKeywords.MainLightShadowScreen, true);
            // }
        }

        private void UpdateAccumulateParams(ComputeCommandBuffer cmd, ref RaytracingSettings settings)
        {
            // Setting keywords can be somewhat expensive on low-end platforms.
            // Previous params are cached to avoid setting the same keywords every frame.
            AccumulateMaterialParams matParams = new AccumulateMaterialParams(ref settings);
            bool paramsDirty = !m_AccumulateMaterialParamsPrev.Equals(ref matParams);    // Checks if the parameters have changed.
            if (!m_AccumulateMaterialParamsPrev.isDirty && !paramsDirty)
                return;

            m_AccumulateMaterialParamsPrev = matParams;
            m_AccumulateMaterialParamsPrev.isDirty = false;
            cmd.SetGlobalVector(id_BlendOffsetId, matParams.blendSampleOffset);
            cmd.SetGlobalInteger(id_AccumulateReflection, matParams.renderMode == RenderMode.FullRes ? 0 : 1);
            cmd.SetGlobalInteger(id_AccumulateFrameIndex, 0);
        }

        private void UpdateCameraData(ComputeCommandBuffer cmd, ref UniversalCameraData cameraData)
        {
            var camera = cameraData.camera;

            cmd.SetRayTracingFloatParam(m_RayTracingShader, id_NearClip, camera.nearClipPlane);
            cmd.SetRayTracingMatrixParam(m_RayTracingShader, id_CameraToWorld, camera.cameraToWorldMatrix);
            cmd.SetRayTracingMatrixParam(m_RayTracingShader, id_CameraInverseProjection, camera.projectionMatrix.inverse);
        }

        private void UpdateCulling(UniversalCameraData cameraData)
        {
            var camera = cameraData.camera;

            m_RaytracingCullingConfig.sphereRadius = camera.farClipPlane * .5f;
            m_RaytracingCullingConfig.sphereCenter = cameraData.worldSpaceCameraPos;
            m_RaytracingCullingConfig.lodParameters.fieldOfView = camera.fieldOfView;
            m_RaytracingCullingConfig.lodParameters.cameraPosition = cameraData.worldSpaceCameraPos;
            m_RaytracingCullingConfig.lodParameters.cameraPixelHeight = camera.pixelHeight;
        }

        internal static TextureHandle CreateCompatibleTexture(RenderGraph renderGraph, in TextureDesc desc, string name, bool clear, FilterMode filterMode)
        {
            var descCompatible = desc;
            descCompatible.msaaSamples = MSAASamples.None;
            descCompatible.useMipMap = false;
            descCompatible.autoGenerateMips = false;
            descCompatible.anisoLevel = 0;
            descCompatible.discardBuffer = false;
            descCompatible.name = name;
            descCompatible.clearBuffer = clear;
            descCompatible.filterMode = filterMode;
            return renderGraph.CreateTexture(descCompatible);
        }

        internal static TextureDesc GetCompatibleDescriptor(TextureDesc desc, int width, int height, GraphicsFormat format)
        {
            desc.width = width;
            desc.height = height;
            desc.format = format;

            desc.msaaSamples = MSAASamples.None;
            desc.useMipMap = false;
            desc.autoGenerateMips = false;
            desc.anisoLevel = 0;
            desc.discardBuffer = false;

            return desc;
        }

        public void RenderMipChain(RenderGraph renderGraph, in TextureHandle source)
        {
            var srcDesc = source.GetDescriptor(renderGraph);

            int tw = srcDesc.width;
            int th = srcDesc.height;
            int iterations = Mathf.FloorToInt(Mathf.Log(Mathf.Max(tw, th), 2f) - 1);
            int mipCount = Mathf.Clamp(iterations, 1, MaxMipBlurCount);

            var colorFormat = QualitySettings.activeColorSpace == ColorSpace.Linear
                ? GraphicsFormat.R8G8B8A8_SRGB
                : GraphicsFormat.R8G8B8A8_UNorm;

            // Setup
            using(new ProfilingScope(ProfilingSampler.Get(URPProfileId.RG_RayReflectionBlurSetup)))
            {
                // Setting keywords can be somewhat expensive on low-end platforms.
                // Previous params are cached to avoid setting the same keywords every frame.

                // Create bloom mip pyramid textures
                {
                    var desc = GetCompatibleDescriptor(srcDesc, tw, th, colorFormat);
                    m_BlurMipDown[0] = CreateCompatibleTexture(renderGraph, desc, m_BlurMipDownName[0], false, FilterMode.Bilinear);
                    m_BlurMipUp[0] = CreateCompatibleTexture(renderGraph, desc, m_BlurMipUpName[0], false, FilterMode.Bilinear);

                    for (int i = 1; i < mipCount; i++)
                    {
                        tw = Mathf.Max(1, tw >> 1);
                        th = Mathf.Max(1, th >> 1);
                        ref TextureHandle mipDown = ref m_BlurMipDown[i];
                        ref TextureHandle mipUp = ref m_BlurMipUp[i];

                        desc.width = tw;
                        desc.height = th;

                        mipDown = CreateCompatibleTexture(renderGraph, desc, m_BlurMipDownName[i], false, FilterMode.Bilinear);
                        mipUp = CreateCompatibleTexture(renderGraph, desc, m_BlurMipUpName[i], false, FilterMode.Bilinear);
                    }
                }
            }

            switch (m_CurrentSettings.reflectionBlurMode)
            {
                case BlurMode.Dual:
                    BlurDual(renderGraph, source, mipCount);
                break;
                case BlurMode.Gaussian:
                    BlurGaussian(renderGraph, source, mipCount);
                break;
            }
        }

        //  Dual Filter, Bandwidth-Efficient Rendering, siggraph2015
        void BlurDual(RenderGraph renderGraph, TextureHandle source, int mipCount)
        {
            using (var builder = renderGraph.AddUnsafePass<BlurPassData>("Blit Blur Mipmaps (Dual)", out var passData, ProfilingSampler.Get(URPProfileId.RayReflectionBlur)))
            {
                passData.mipCount = mipCount;
                passData.material = m_BlurMat;
                passData.sourceTexture = source;
                passData.blurMipDown = m_BlurMipDown;
                passData.blurMipUp = m_BlurMipUp;

                // TODO RENDERGRAPH: properly setup dependencies between passes
                builder.AllowPassCulling(false);

                builder.UseTexture(source, AccessFlags.ReadWrite);
                for (int i = 0; i < mipCount; i++)
                {
                    builder.UseTexture(m_BlurMipDown[i], AccessFlags.ReadWrite);
                }

                builder.SetGlobalTextureAfterPass(passData.sourceTexture, id_ScreenSpaceReflectionTexture);

                builder.SetRenderFunc((BlurPassData data, UnsafeGraphContext context) =>
                {
                    if (!m_Rendered) return;
                    m_Rendered = false;

                    var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);

                    var loadAction = RenderBufferLoadAction.DontCare;   // Blit - always write all pixels
                    var storeAction = RenderBufferStoreAction.Store;    // Blit - always read by then next Blit

                    // ARM: Bandwidth-Efficient Rendering, siggraph2015
                    // Downsample - dual pyramid, fixed Kawase0 blur on shrinking targets.
                    using(new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.RG_RayReflectionBlurDownsample)))
                    {
                        Blitter.BlitCameraTexture(cmd, data.sourceTexture, data.blurMipDown[0], loadAction, storeAction, data.material, 2);
                        TextureHandle lastDown = data.blurMipDown[0];
                        for (int i = 1; i < data.mipCount; i++)
                        {
                            TextureHandle src = data.blurMipDown[i - 1];
                            TextureHandle dst = data.blurMipDown[i];

                            Blitter.BlitCameraTexture(cmd, src, dst, loadAction, storeAction, data.material, 2);
                        }
                    }

                    using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.RG_RayReflectionBlurCopy)))
                    {
                        RTHandle dst = data.sourceTexture;
                        Vector2 viewportScale = dst.useScaling ? new Vector2(dst.rtHandleProperties.rtHandleScale.x, dst.rtHandleProperties.rtHandleScale.y) : Vector2.one;
                        for (int i = 0; i < data.mipCount; i++)
                        {
                            TextureHandle src = data.blurMipDown[i];

                            CoreUtils.SetRenderTarget(cmd, dst, ClearFlag.None, Color.clear, i + 1);
                            Blitter.BlitTexture2D(cmd, src, viewportScale, 0, false);
                        }
                    }
                });
            }
        }

        void BlurGaussian(RenderGraph renderGraph, TextureHandle source, int mipCount)
        {
            using (var builder = renderGraph.AddUnsafePass<BlurPassData>("Blit Blur Mipmaps", out var passData, ProfilingSampler.Get(URPProfileId.RayReflectionBlur)))
            {
                passData.mipCount = mipCount;
                passData.material = m_BlurMat;
                passData.sourceTexture = source;
                passData.blurMipDown = m_BlurMipDown;
                passData.blurMipUp = m_BlurMipUp;

                // TODO RENDERGRAPH: properly setup dependencies between passes
                builder.AllowPassCulling(false);

                builder.UseTexture(source, AccessFlags.ReadWrite);
                for (int i = 0; i < mipCount; i++)
                {
                    builder.UseTexture(m_BlurMipDown[i], AccessFlags.ReadWrite);
                    builder.UseTexture(m_BlurMipUp[i], AccessFlags.ReadWrite);
                }

                builder.SetGlobalTextureAfterPass(passData.sourceTexture, id_ScreenSpaceReflectionTexture);

                builder.SetRenderFunc((BlurPassData data, UnsafeGraphContext context) =>
                {
                    // TODO: can't call BlitTexture with unsafe command buffer
                    var cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);

                    var loadAction = RenderBufferLoadAction.DontCare; // Blit - always write all pixels
                    var storeAction = RenderBufferStoreAction.Store; // Blit - always read by then next Blit

                    // Downsample - gaussian pyramid
                    // Classic two pass gaussian blur - use mipUp as a temporary target
                    //   First pass does 2x downsampling + 9-tap gaussian
                    //   Second pass does 9-tap gaussian using a 5-tap filter + bilinear filtering
                    using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.RG_RayReflectionBlurDownsample)))
                    {
                        Blitter.BlitCameraTexture(cmd, data.sourceTexture, data.blurMipUp[0], loadAction, storeAction, passData.material, 0);
                        Blitter.BlitCameraTexture(cmd, data.blurMipUp[0], data.blurMipDown[0], loadAction, storeAction, passData.material, 1);

                        TextureHandle lastDown = data.blurMipDown[0];
                        for (int i = 1; i < mipCount; i++)
                        {
                            TextureHandle mipDown = data.blurMipDown[i];
                            TextureHandle mipUp = data.blurMipUp[i];

                            Blitter.BlitCameraTexture(cmd, lastDown, mipUp, loadAction, storeAction, passData.material, 0);
                            Blitter.BlitCameraTexture(cmd, mipUp, mipDown, loadAction, storeAction, passData.material, 1);

                            lastDown = mipDown;
                        }
                    }

                    using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.RG_RayReflectionBlurCopy)))
                    {
                        RTHandle dst = data.sourceTexture;
                        Vector2 viewportScale = dst.useScaling ? new Vector2(dst.rtHandleProperties.rtHandleScale.x, dst.rtHandleProperties.rtHandleScale.y) : Vector2.one;
                        for (int i = 0; i < data.mipCount; i++)
                        {
                            TextureHandle src = data.blurMipDown[i];

                            CoreUtils.SetRenderTarget(cmd, dst, ClearFlag.None, Color.clear, i + 1);
                            Blitter.BlitTexture2D(cmd, src, viewportScale, 0, false);
                        }
                    }
                });
            }
        }

        /// <inheritdoc cref="IRenderGraphRecorder.RecordRenderGraph"/>
        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            if (m_PrevTargetFrameRate != m_CurrentSettings.targetFrameRate)
            {
                m_PrevTargetFrameRate = m_CurrentSettings.targetFrameRate;
                if (m_PrevTargetFrameRate <= 0)
                {
                    m_UpdateTarget = 0f;
                }
                else m_UpdateTarget = 1f / m_PrevTargetFrameRate;

                m_CaptureUpdate = 100;
            }

            UpdateTextures(renderGraph, cameraData);

            var reflectionTarget = renderGraph.ImportTexture(m_ReflectionTargetHandle);

            UpdateAccelerationStructure();

            using (var builder = renderGraph.AddComputePass<ReflectionPassData>("Reflection", out var passData, ProfilingSampler.Get(URPProfileId.RayReflection)))
            {
                var desc = reflectionTarget.GetDescriptor(renderGraph);
                passData.rayTracingShader = m_RayTracingShader;
                passData.accelerationStructure = m_AccelerationStructure;
                passData.reflectionTarget = reflectionTarget;
                passData.width = desc.width;
                passData.height = desc.height;
                passData.cameraData = cameraData;

                builder.UseTexture(passData.reflectionTarget, AccessFlags.Write);
                builder.AllowGlobalStateModification(true);

                if (!m_CurrentSettings.generateReflectionMips)
                    builder.SetGlobalTextureAfterPass(passData.reflectionTarget, id_ScreenSpaceReflectionTexture);

                builder.SetRenderFunc((ReflectionPassData data, ComputeGraphContext context) =>
                {
                    var cmd = context.cmd;

                    UpdateCulling(data.cameraData);
                    m_CullUpdate += Time.unscaledDeltaTime;

                    if (m_CullUpdate >= Mathf.Max(0.033f, m_UpdateTarget))
                    {
                        m_CullUpdate = 0;

                        m_AccelerationStructure.ClearInstances();
                        m_AccelerationStructure.CullInstances(ref m_RaytracingCullingConfig);
                        m_AccelerationStructure.Build();
                    }

                    m_CaptureUpdate += Time.unscaledDeltaTime;
                    if (m_CaptureUpdate >= m_UpdateTarget)
                    {
                        // Debug.Log($"Finish {m_CaptureUpdate}");
                        m_CaptureUpdate = 0;

                        UpdateParams(cmd, ref m_CurrentSettings, ref passData.cameraData);

                        UpdateCameraData(cmd, ref passData.cameraData);

                        UpdateAccumulateParams(cmd, ref m_CurrentSettings);

                        if (m_CurrentSettings.renderMode != RenderMode.FullRes)
                            cmd.SetGlobalInteger(id_AccumulateFrameIndex, m_FrameIndex & 1);

                        cmd.SetGlobalInteger(id_FrameIndex, m_FrameIndex);

                        cmd.SetRayTracingTextureParam(passData.rayTracingShader, id_ReflectionRenderTarget,
                            data.reflectionTarget);

                        cmd.SetRayTracingShaderPass(passData.rayTracingShader, "RaytracingLit");
                        cmd.SetRayTracingAccelerationStructure(passData.rayTracingShader, id_AccelerationStructure,
                            passData.accelerationStructure);

                        cmd.DispatchRays(passData.rayTracingShader, "Raytracer", (uint)data.width, (uint)data.height, 1u, cameraData.camera);

                        m_FrameIndex = (m_FrameIndex + 1) % 1024;
                        m_Rendered = true;
                    } // else Debug.Log($"Tick {m_CaptureUpdate} {m_UpdateTarget}");
                });
            }

            if (!m_CurrentSettings.generateReflectionMips) return;

            if (m_CurrentSettings.reflectionBlurMode == BlurMode.Native)
            {
                using (var builder = renderGraph.AddUnsafePass<MipPassData>("Mip Gen", out var passData,
                           ProfilingSampler.Get(URPProfileId.RayReflection)))
                {
                    passData.reflectionTarget = reflectionTarget;

                    builder.AllowPassCulling(false);
                    builder.UseTexture(passData.reflectionTarget, AccessFlags.Write);
                    builder.AllowGlobalStateModification(true);

                    builder.SetGlobalTextureAfterPass(passData.reflectionTarget, id_ScreenSpaceReflectionTexture);

                    builder.SetRenderFunc((MipPassData data, UnsafeGraphContext context) =>
                    {
                        if (!m_Rendered) return;
                        var cmd = context.cmd;
                        cmd.GenerateMips(data.reflectionTarget);
                        m_Rendered = false;
                    });
                }
            }
            else
            {
                RenderMipChain(renderGraph, reflectionTarget);
            }
        }

        public void Dispose()
        {
            m_ReflectionTargetHandle?.Release();
            m_ReflectionTargetHandle = null;

            m_AccelerationStructure?.Dispose();
            m_AccelerationStructure = null;

            Shader.SetKeyword(ShaderGlobalKeywords.ReflectionScreen, false);
            Shader.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBilinear, false);
            Shader.SetKeyword(ShaderGlobalKeywords.ReflectionScreenTrilinear, false);
            Shader.SetKeyword(ShaderGlobalKeywords.ReflectionScreenBicubic, false);
        }
    }
}
