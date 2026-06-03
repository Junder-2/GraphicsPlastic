using System;
using System.Runtime.CompilerServices;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace UnityEngine.Rendering.Universal
{
    internal class InterlaceRenderingPass : ScriptableRenderPass
    {
        // Private Variables
        private Material m_Material;
        private RenderTextureDescriptor m_InterlacePassDescriptor;
        private InterlacedRenderingSettings m_CurrentSettings;
        private RTHandle m_AccumulationTextureHandle;
        private bool frameIndex;

        // Statics
        private static readonly int s_BlendOffsetId = Shader.PropertyToID("_BlendSampleOffset");
        private static readonly int s_TargetFrameDeltaId = Shader.PropertyToID("_TargetFrameDelta");
        private static readonly int s_FrameIndex = Shader.PropertyToID("_FrameIndex");
        private static readonly int s_AccumulateId = Shader.PropertyToID("_AccumulateTex");

#if URP_COMPATIBILITY_MODE
        private RTHandle[] m_SSAOTextures = new RTHandle[4];

        private SSAOPassData m_PassData;
        private ScriptableRenderer m_Renderer = null;

        private static readonly int[] m_BilateralTexturesIndices            = { 0, 1, 2, 3 };
        private static readonly ShaderPasses[] m_BilateralPasses            = { ShaderPasses.BilateralBlurHorizontal, ShaderPasses.BilateralBlurVertical, ShaderPasses.BilateralBlurFinal };
        private static readonly ShaderPasses[] m_BilateralAfterOpaquePasses = { ShaderPasses.BilateralBlurHorizontal, ShaderPasses.BilateralBlurVertical, ShaderPasses.BilateralAfterOpaque };

        private static readonly int[] m_GaussianTexturesIndices             = { 0, 1, 3, 3 };
        private static readonly ShaderPasses[] m_GaussianPasses             = { ShaderPasses.GaussianBlurHorizontal, ShaderPasses.GaussianBlurVertical };
        private static readonly ShaderPasses[] m_GaussianAfterOpaquePasses  = { ShaderPasses.GaussianBlurHorizontal, ShaderPasses.GaussianAfterOpaque };

        private static readonly int[] m_KawaseTexturesIndices               = { 0, 3 };
        private static readonly ShaderPasses[] m_KawasePasses               = { ShaderPasses.KawaseBlur };
        private static readonly ShaderPasses[] m_KawaseAfterOpaquePasses    = { ShaderPasses.KawaseAfterOpaque };
#endif

        // Structs
        private struct InterlaceMaterialParams
        {
            internal float targetFrameDelta;
            internal Vector4 blendSampleOffset;

            internal InterlaceMaterialParams(ref InterlacedRenderingSettings settings)
            {
                targetFrameDelta = 1f / (1f / settings.FrameDeltaTarget);

                Vector2 offset = Vector2.zero;
                switch (settings.Pattern)
                {
                    case InterlacedRenderingSettings.InterlacePattern.Lines:
                        offset.x = 0;
                        offset.y = settings.VerticalResolutionFactor;
                        break;
                    case InterlacedRenderingSettings.InterlacePattern.Checkerboard:
                        offset.x = settings.VerticalResolutionFactor;
                        offset.y = settings.VerticalResolutionFactor;
                        break;
                }

                blendSampleOffset = new Vector4(
                    offset.x,                               // x
                    offset.y,                               // y
                    offset.x != 0 ? 1f / offset.x: 0,       // 1 / x
                    offset.y != 0 ? 1f / offset.y : 0    // 1 / y
                );
            }

            internal bool Equals(ref InterlaceMaterialParams other)
            {
                return Mathf.Approximately(targetFrameDelta, other.targetFrameDelta)
                       && blendSampleOffset == other.blendSampleOffset
                       ;
            }
        }
        private InterlaceMaterialParams m_InterlaceParamsPrev = new InterlaceMaterialParams();

        internal InterlaceRenderingPass()
        {
            m_CurrentSettings = new InterlacedRenderingSettings();
#if URP_COMPATIBILITY_MODE
            m_PassData = new SSAOPassData();
#endif
        }

        internal bool Setup(ref InterlacedRenderingSettings featureSettings, ref ScriptableRenderer renderer, ref Material material)
        {
            m_Material = material;
            m_CurrentSettings = featureSettings;
#if URP_COMPATIBILITY_MODE
            m_Renderer = renderer;
#endif

            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            ConfigureInput(ScriptableRenderPassInput.Color);

            return m_Material != null;
        }

#if URP_COMPATIBILITY_MODE
        private static bool IsAfterOpaquePass(ref ShaderPasses pass)
        {
            return pass == ShaderPasses.BilateralAfterOpaque
                   || pass == ShaderPasses.GaussianAfterOpaque
                   || pass == ShaderPasses.KawaseAfterOpaque;
        }

#endif

        private void SetupKeywordsAndParameters(ref InterlacedRenderingSettings settings, ref UniversalCameraData cameraData)
        {
            // Setting keywords can be somewhat expensive on low-end platforms.
            // Previous params are cached to avoid setting the same keywords every frame.
            InterlaceMaterialParams matParams = new InterlaceMaterialParams(ref settings);
            bool paramsDirty = !m_InterlaceParamsPrev.Equals(ref matParams);    // Checks if the parameters have changed.
            bool isParamsPropertySet = m_Material.HasProperty(s_BlendOffsetId); // Checks if the parameters have been set on the material.
            if (!paramsDirty && isParamsPropertySet)
                return;

            m_InterlaceParamsPrev = matParams;
            m_Material.SetVector(s_BlendOffsetId, matParams.blendSampleOffset);
            m_Material.SetFloat(s_TargetFrameDeltaId, matParams.targetFrameDelta);
        }

        /*----------------------------------------------------------------------------------------------------------------------------------------
         ------------------------------------------------------------- RENDER-GRAPH --------------------------------------------------------------
         ----------------------------------------------------------------------------------------------------------------------------------------*/

        private class InterlacePassData
        {
            internal TextureHandle inputTexture;
            internal TextureHandle accumulateTexture;
            internal Material material;
            internal UniversalCameraData cameraData;
        }

        private class PassData
        {
            internal TextureHandle sourceTexture;
            internal TextureHandle destTexture;
        }

        private void InitInterlacePassData(ref InterlacePassData data)
        {
            data.material = m_Material;
        }

        private static Vector4 GetScaleBias(RTHandle source, RTHandle destination, UniversalCameraData cameraData)
        {
            Vector2 viewportScale = source.useScaling ? new Vector2(source.rtHandleProperties.rtHandleScale.x, source.rtHandleProperties.rtHandleScale.y) : Vector2.one;
            var yflip = cameraData.IsRenderTargetProjectionMatrixFlipped(destination);
            Vector4 scaleBias = !yflip ? new Vector4(viewportScale.x, -viewportScale.y, 0, viewportScale.y) : new Vector4(viewportScale.x, viewportScale.y, 0, 0);

            return scaleBias;
        }

        /// <inheritdoc cref="IRenderGraphRecorder.RecordRenderGraph"/>
        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            TextureHandle source, target, accumulate;
            source = resourceData.activeColorTexture;

            var desc = cameraData.cameraTargetDescriptor;

            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;
            // desc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
            RenderingUtils.ReAllocateHandleIfNeeded(ref m_AccumulationTextureHandle, desc, name: "_MotionBlurTarget");
            accumulate = renderGraph.ImportTexture(m_AccumulationTextureHandle);
            // Debug.Log($"RecordRenderGraph {desc.dimension}");

            // Update keywords and other shader params
            SetupKeywordsAndParameters(ref m_CurrentSettings, ref cameraData);

            using (var builder = renderGraph.AddRasterRenderPass<InterlacePassData>("Blend", out var passData, profilingSampler))
            {
                passData.inputTexture = source;
                passData.accumulateTexture = accumulate;
                InitInterlacePassData(ref passData);
                builder.UseTexture(passData.inputTexture, AccessFlags.Read);
                builder.SetRenderAttachment(passData.accumulateTexture, 0, AccessFlags.Write);
                builder.AllowGlobalStateModification(true);

                builder.SetRenderFunc((InterlacePassData data, RasterGraphContext context) =>
                {
                    frameIndex = !frameIndex;
                    data.material.SetFloat(s_FrameIndex, frameIndex ? 1 : 0);
                    Blitter.BlitTexture(context.cmd, data.inputTexture, new Vector4(1, 1, 0, 0), data.material, 0);
                });
            }

            //Swap for next pass;
            source = accumulate;
            target = resourceData.activeColorTexture;

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("Copy Back Blend", out var passData, profilingSampler))
            {
                passData.sourceTexture = source;
                passData.destTexture = target;
                builder.UseTexture(source, AccessFlags.Read);
                builder.SetRenderAttachment(target, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Vector4 viewportScale = GetScaleBias(source, passData.destTexture, cameraData);
                    Blitter.BlitTexture(context.cmd, data.sourceTexture, viewportScale, 0.0f, false);
                });
            }
        }

        /*----------------------------------------------------------------------------------------------------------------------------------------
         ------------------------------------------------------------- RENDER-GRAPH --------------------------------------------------------------
         ----------------------------------------------------------------------------------------------------------------------------------------*/

#if URP_COMPATIBILITY_MODE
        /// <inheritdoc/>
        [Obsolete(DeprecationMessage.CompatibilityScriptingAPIObsoleteFrom2023_3)]
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            ContextContainer frameData = renderingData.frameData;
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            // Fill in the Pass data...
            InitSSAOPassData(ref m_PassData);

            // Update keywords and other shader params
            SetupKeywordsAndParameters(ref m_CurrentSettings, ref cameraData);

            // Set up the descriptors
            int downsampleDivider = m_CurrentSettings.Downsample ? 2 : 1;
            RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
            descriptor.msaaSamples = 1;
            descriptor.depthStencilFormat = GraphicsFormat.None;

            // AO PAss
            m_AOPassDescriptor = descriptor;
            m_AOPassDescriptor.width /= downsampleDivider;
            m_AOPassDescriptor.height /= downsampleDivider;
            bool useRedComponentOnly = m_SupportsR8RenderTextureFormat && m_BlurType > BlurTypes.Bilateral;
            m_AOPassDescriptor.colorFormat = useRedComponentOnly ? RenderTextureFormat.R8 : RenderTextureFormat.ARGB32;

            // Allocate textures for the AO and blur
            RenderingUtils.ReAllocateHandleIfNeeded(ref m_SSAOTextures[0], m_AOPassDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_SSAO_OcclusionTexture0");
            RenderingUtils.ReAllocateHandleIfNeeded(ref m_SSAOTextures[1], m_AOPassDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_SSAO_OcclusionTexture1");
            RenderingUtils.ReAllocateHandleIfNeeded(ref m_SSAOTextures[2], m_AOPassDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_SSAO_OcclusionTexture2");

            // Upsample setup
            m_AOPassDescriptor.width *= downsampleDivider;
            m_AOPassDescriptor.height *= downsampleDivider;
            m_AOPassDescriptor.colorFormat = m_SupportsR8RenderTextureFormat ? RenderTextureFormat.R8 : RenderTextureFormat.ARGB32;

            // Allocate texture for the final SSAO results
            RenderingUtils.ReAllocateHandleIfNeeded(ref m_SSAOTextures[3], m_AOPassDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_SSAO_OcclusionTexture");
            PostProcessUtils.SetSourceSize(cmd, m_SSAOTextures[3]);

            // Disable obsolete warning for internal usage
            #pragma warning disable CS0618
            // Configure targets and clear color
            ConfigureTarget(m_CurrentSettings.AfterOpaque ? m_Renderer.cameraColorTargetHandle : m_SSAOTextures[3]);
            ConfigureClear(ClearFlag.None, Color.white);
            #pragma warning restore CS0618
        }

        /// <inheritdoc/>
        [Obsolete(DeprecationMessage.CompatibilityScriptingAPIObsoleteFrom2023_3)]
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null)
            {
                Debug.LogErrorFormat(
                    "{0}.Execute(): Missing material. ScreenSpaceAmbientOcclusion pass will not execute. Check for missing reference in the renderer resources.",
                    GetType().Name);
                return;
            }

            var cmd = renderingData.commandBuffer;
            using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.SSAO)))
            {
                // We only want URP shaders to sample SSAO if After Opaque is off.
                if (!m_CurrentSettings.AfterOpaque)
                    cmd.SetKeyword(ShaderGlobalKeywords.ScreenSpaceOcclusion, true);

                cmd.SetGlobalTexture(k_SSAOTextureName, m_SSAOTextures[3]);

                #if ENABLE_VR && ENABLE_XR_MODULE
                    bool isFoveatedEnabled = false;
                    if (renderingData.cameraData.xr.supportsFoveatedRendering)
                    {
                        // If we are downsampling we can't use the VRS texture
                        // If it's a non uniform raster foveated rendering has to be turned off because it will keep applying non uniform for the other passes.
                        // When calculating normals from depth, this causes artifacts that are amplified from VRS when going to say 4x4. Thus we disable foveated because of that
                        if (m_CurrentSettings.Downsample || SystemInfo.foveatedRenderingCaps.HasFlag(FoveatedRenderingCaps.NonUniformRaster) ||
                            (SystemInfo.foveatedRenderingCaps.HasFlag(FoveatedRenderingCaps.FoveationImage) && m_CurrentSettings.Source == ScreenSpaceAmbientOcclusionSettings.DepthSource.Depth))
                        {
                            cmd.SetFoveatedRenderingMode(FoveatedRenderingMode.Disabled);
                        }
                        // If we aren't downsampling and it's a VRS texture we can apply foveation in this case
                        else if (SystemInfo.foveatedRenderingCaps.HasFlag(FoveatedRenderingCaps.FoveationImage))
                        {
                            cmd.SetFoveatedRenderingMode(FoveatedRenderingMode.Enabled);
                            isFoveatedEnabled = true;
                        }
                    }
                #endif

                GetPassOrder(m_BlurType, m_CurrentSettings.AfterOpaque, out int[] textureIndices, out ShaderPasses[] shaderPasses);

                // Execute the SSAO Occlusion pass
                RTHandle cameraDepthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                RenderAndSetBaseMap(ref cmd, ref renderingData, ref renderingData.cameraData.renderer, ref m_Material, ref cameraDepthTargetHandle, ref m_SSAOTextures[0], ShaderPasses.AmbientOcclusion);

                // Execute the Blur Passes
                for (int i = 0; i < shaderPasses.Length; i++)
                {
                    int baseMapIndex = textureIndices[i];
                    int targetIndex = textureIndices[i + 1];
                    RenderAndSetBaseMap(ref cmd, ref renderingData, ref renderingData.cameraData.renderer, ref m_Material, ref m_SSAOTextures[baseMapIndex], ref m_SSAOTextures[targetIndex], shaderPasses[i]);
                }

                // Set the global SSAO Params
                cmd.SetGlobalVector(s_AmbientOcclusionParamID, new Vector4(1f, 0f, 0f, m_CurrentSettings.DirectLightingStrength));
                #if ENABLE_VR && ENABLE_XR_MODULE
                    // Cleanup, making sure it doesn't stay enabled for a pass after that should not have it on
                    if (isFoveatedEnabled)
                        cmd.SetFoveatedRenderingMode(FoveatedRenderingMode.Disabled);
                #endif
            }
        }

        private static void RenderAndSetBaseMap(ref CommandBuffer cmd, ref RenderingData renderingData, ref ScriptableRenderer renderer, ref Material mat, ref RTHandle baseMap, ref RTHandle target, ShaderPasses pass)
        {
            if (IsAfterOpaquePass(ref pass))
            {
                // Disable obsolete warning for internal usage
                #pragma warning disable CS0618
                Blitter.BlitCameraTexture(cmd, baseMap, renderer.cameraColorTargetHandle, RenderBufferLoadAction.Load, RenderBufferStoreAction.Store, mat, (int)pass);
                #pragma warning restore CS0618
            }

            else if (baseMap.rt == null)
            {
                // Obsolete usage of RTHandle aliasing a RenderTargetIdentifier
                Vector2 viewportScale = baseMap.useScaling ? new Vector2(baseMap.rtHandleProperties.rtHandleScale.x, baseMap.rtHandleProperties.rtHandleScale.y) : Vector2.one;

                // Will set the correct camera viewport as well.
                CoreUtils.SetRenderTarget(cmd, target);
                Blitter.BlitTexture(cmd, baseMap.nameID, viewportScale, mat, (int)pass);
            }

            else
                Blitter.BlitCameraTexture(cmd, baseMap, target, mat, (int)pass);
        }

        private static void GetPassOrder(BlurTypes blurType, bool isAfterOpaque, out int[] textureIndices, out ShaderPasses[] shaderPasses)
        {
            switch (blurType)
            {
                case BlurTypes.Bilateral:
                    textureIndices = m_BilateralTexturesIndices;
                    shaderPasses = isAfterOpaque ? m_BilateralAfterOpaquePasses : m_BilateralPasses;
                    break;
                case BlurTypes.Gaussian:
                    textureIndices = m_GaussianTexturesIndices;
                    shaderPasses = isAfterOpaque ? m_GaussianAfterOpaquePasses : m_GaussianPasses;
                    break;
                case BlurTypes.Kawase:
                    textureIndices = m_KawaseTexturesIndices;
                    shaderPasses = isAfterOpaque ? m_KawaseAfterOpaquePasses : m_KawasePasses;
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }
        }
#endif

        /// <inheritdoc/>
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd == null)
                throw new ArgumentNullException("cmd");
        }

        public void Dispose()
        {
            m_InterlaceParamsPrev = default;
            m_AccumulationTextureHandle?.Release();
        }
    }
}
