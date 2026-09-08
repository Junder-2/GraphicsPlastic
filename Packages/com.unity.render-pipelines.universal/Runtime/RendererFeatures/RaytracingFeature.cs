using System;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal.Internal;
using UnityEngine.Serialization;

namespace UnityEngine.Rendering.Universal
{
    using NormalFormatQuality = DepthNormalOnlyPass.NormalFormatQuality;

    [Serializable]
    internal class RaytracingSettings
    {
        [SerializeField, Range(-5, 5)] internal float lodBias = 1;
        [SerializeField, Range(0.001f, 1)] internal float renderScale = 1f;
        [SerializeField, Range(0.001f, 1)] internal float transparentRenderScale = 1f;
        [SerializeField] internal LayerMask updateLayers;
        [SerializeField, Min(0)] internal float cullDistance = 100f;

        [SerializeField] internal bool raytraceShadows = true;
        [SerializeField] internal bool raytraceReflections = true;

        [SerializeField, Range(1, 5)] internal byte maxReflectionDepth = 1;
        [SerializeField, Range(0, 5)] internal byte maxTransparentDepth = 1;
        [SerializeField] internal bool reflectionTransparent = false;
        [SerializeField] internal bool renderReflectionsMainShadows = true;

        [SerializeField] internal RenderMode renderMode = RenderMode.FullRes;
        [SerializeField, Range(0.001f, 1)] internal float renderNoiseFraction = .5f;
        [SerializeField] internal SamplingMode samplingMode = SamplingMode.Point;
        [SerializeField] internal NormalFormatQuality normalFormatQuality = NormalFormatQuality.Default;
        [SerializeField, Range(0, 300)] internal int targetFrameRate;

        [SerializeField] internal bool generateReflectionMips;
        [SerializeField] internal BlurMode reflectionBlurMode = BlurMode.Dual;

        internal enum RenderMode
        {
            FullRes,
            HalfLines,
            HalfCheckerboard,
            InterleavedGradientNoise,
        }

        internal enum SamplingMode
        {
            Point,
            Bilinear,
            Trilinear,
            Bicubic
        }

        internal enum BlurMode
        {
            [Tooltip("Native hardware mip gen.")]
            Native,
            [Tooltip("Balanced quality and speed.")]
            Dual,
            [Tooltip("Best quality.")]
            Gaussian,
        }

        internal void Validate()
        {
            transparentRenderScale = Mathf.Min(transparentRenderScale, renderScale);
        }
    }

    [Serializable]
    [SupportedOnRenderPipeline(typeof(UniversalRenderPipelineAsset))]
    [Categorization.CategoryInfo(Name = "R: Raytracing Shader", Order = 1000)]
    [Categorization.ElementInfo(Order = 0), HideInInspector]
    class RaytracingPersistentResources : IRenderPipelineResources
    {
        [SerializeField]
        [ResourcePath("Shaders/Raytracing/Raytracer.raytrace")]
        RayTracingShader m_RayShader;

        public RayTracingShader RayShader
        {
            get => m_RayShader;
            set => this.SetValueAndNotify(ref m_RayShader, value);
        }

        [SerializeField]
        [ResourcePath("Shaders/Raytracing/RayReflectionBlur.shader")]
        Shader m_BlurShader;

        public Shader BlurShader
        {
            get => m_BlurShader;
            set => this.SetValueAndNotify(ref m_BlurShader, value);
        }

        public bool isAvailableInPlayerBuild => true;

        [SerializeField][HideInInspector] private int m_Version = 0;

        /// <summary>Current version of the resource container. Used only for upgrading a project.</summary>
        public int version => m_Version;
    }

    [DisallowMultipleRendererFeature("Raytracing Feature")]
    [Tooltip("Raytracing Feature")]
    public class RaytracingFeature : ScriptableRendererFeature
    {
#if UNITY_EDITOR
        [UnityEditor.ShaderKeywordFilter.SelectIf(true, keywordNames: ShaderKeywordStrings.ReflectionScreen)]
        private const bool k_RequiresReflectionKeyword = true;
#endif

        [SerializeField] private RaytracingSettings settings = new ();

        private RaytracingPass m_RaytracingPass = null;
        private RayTracingShader m_RayTracingShader;

        private Shader m_BlurShader;
        private Material m_BlurMaterial;

        /// <inheritdoc/>
        public override void Create()
        {
            if (!isActive)
            {
                if (m_RaytracingPass == null) return;
                m_RaytracingPass?.Dispose();
                m_RaytracingPass = null;
                return;
            }

            // Create the pass...
            if (m_RaytracingPass == null)
                m_RaytracingPass = new RaytracingPass();

            m_RaytracingPass.ResetParams();
        }

        /// <inheritdoc/>
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (UniversalRenderer.IsOffscreenDepthTexture(ref renderingData.cameraData))
                return;

            if (!TryPrepareResources())
                return;

            settings.Validate();
            if (m_RaytracingPass.Setup(settings, m_RayTracingShader, m_BlurMaterial))
                renderer.EnqueuePass(m_RaytracingPass);
        }

        /// <inheritdoc/>
        protected override void Dispose(bool disposing)
        {
            // Debug.Log("Hello?");
            m_RaytracingPass?.Dispose();
            m_RaytracingPass = null;
        }

        bool TryPrepareResources()
        {
            if (m_RayTracingShader == null || m_BlurShader == null)
            {
                if (!GraphicsSettings.TryGetRenderPipelineSettings<RaytracingPersistentResources>(out var raytracingPersistentResources))
                {
                    Debug.LogErrorFormat(
                        $"Couldn't find the required resources for the {nameof(RaytracingFeature)} render feature. If this exception appears in the Player, make sure at least one {nameof(ScreenSpaceAmbientOcclusion)} render feature is enabled or adjust your stripping settings.");
                    return false;
                }

                m_RayTracingShader = raytracingPersistentResources.RayShader;
                m_BlurShader = raytracingPersistentResources.BlurShader;
            }

            if (m_BlurMaterial == null && m_BlurShader != null)
                m_BlurMaterial = CoreUtils.CreateEngineMaterial(m_BlurShader);

            if (m_BlurMaterial == null)
            {
                Debug.LogError($"{GetType().Name}.AddRenderPasses(): Missing material. {name} render pass will not be added.");
                return false;
            }

            return true;
        }
    }
}
