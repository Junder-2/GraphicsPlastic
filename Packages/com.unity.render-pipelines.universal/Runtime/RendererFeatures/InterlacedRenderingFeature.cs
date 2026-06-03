// PLASTIC

using System;
#if UNITY_EDITOR
using ShaderKeywordFilter = UnityEditor.ShaderKeywordFilter;
#endif

namespace UnityEngine.Rendering.Universal
{
    [Serializable]
    internal class InterlacedRenderingSettings
    {
        [SerializeField] internal float FrameDeltaTarget = 60;
        [SerializeField] internal InterlacePattern Pattern = InterlacePattern.Lines;
        [SerializeField] internal int VerticalResolutionFactor = 2;


        internal enum InterlacePattern
        {
            Lines,
            Checkerboard
        }
    }

    [Serializable]
    [SupportedOnRenderPipeline(typeof(UniversalRenderPipelineAsset))]
    [Categorization.CategoryInfo(Name = "R: InterlacedRendering Shader", Order = 1000)]
    [Categorization.ElementInfo(Order = 0), HideInInspector]
    class InterlacedRenderingPersistentResources : IRenderPipelineResources
    {
        [SerializeField]
        [ResourcePath("Shaders/Utils/TemporalBlend.shader")]
        Shader m_Shader;

        public Shader Shader
        {
            get => m_Shader;
            set => this.SetValueAndNotify(ref m_Shader, value);
        }

        public bool isAvailableInPlayerBuild => true;

        [SerializeField][HideInInspector] private int m_Version = 0;

        /// <summary>Current version of the resource container. Used only for upgrading a project.</summary>
        public int version => m_Version;
    }

    /// <summary>
    /// The class for the SSAO renderer feature.
    /// </summary>
    [SupportedOnRenderer(typeof(UniversalRendererData))]
    [DisallowMultipleRendererFeature("InterlacedRenderingFeature")]
    [Tooltip("InterlacedRenderingFeature.")]
    public class InterlacedRenderingFeature : ScriptableRendererFeature
    {
        // Serialized Fields
        [SerializeField] private InterlacedRenderingSettings m_Settings = new InterlacedRenderingSettings();

        // Private Fields
        private Material m_Material;
        private InterlaceRenderingPass m_InterlacePass = null;
        private Shader m_Shader;

        // Internal / Constants
        internal ref InterlacedRenderingSettings settings => ref m_Settings;

        /// <inheritdoc/>
        public override void Create()
        {
            // Create the pass...
            if (m_InterlacePass == null)
                m_InterlacePass = new InterlaceRenderingPass();
        }

        /// <inheritdoc/>
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (UniversalRenderer.IsOffscreenDepthTexture(ref renderingData.cameraData))
                return;

            if (!TryPrepareResources())
                return;

            bool shouldAdd = m_InterlacePass.Setup(ref m_Settings, ref renderer, ref m_Material);
            if (shouldAdd)
                renderer.EnqueuePass(m_InterlacePass);
        }

        /// <inheritdoc/>
        protected override void Dispose(bool disposing)
        {
            m_InterlacePass?.Dispose();
            m_InterlacePass = null;
            CoreUtils.Destroy(m_Material);
        }

        bool TryPrepareResources()
        {
            if (m_Shader == null)
            {
                if (!GraphicsSettings.TryGetRenderPipelineSettings<InterlacedRenderingPersistentResources>(out var ssaoPersistentResources))
                {
                    Debug.LogErrorFormat(
                        $"Couldn't find the required resources for the {nameof(InterlacedRenderingFeature)} render feature. If this exception appears in the Player, make sure at least one {nameof(ScreenSpaceAmbientOcclusion)} render feature is enabled or adjust your stripping settings.");
                    return false;
                }

                m_Shader = ssaoPersistentResources.Shader;
            }

            if (m_Material == null && m_Shader != null)
                m_Material = CoreUtils.CreateEngineMaterial(m_Shader);

            if (m_Material == null)
            {
                Debug.LogError($"{GetType().Name}.AddRenderPasses(): Missing material. {name} render pass will not be added.");
                return false;
            }

            return true;

        }
    }
}
