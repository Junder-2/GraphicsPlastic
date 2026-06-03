Shader "Hidden/Universal Render Pipeline/TemporalBlend"
{
    HLSLINCLUDE
        #pragma editor_sync_compilation

        #pragma vertex Vert
        #pragma fragment BlendFrag
    ENDHLSL

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }
        Cull Off
        ZWrite Off
        ZTest Always
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "TemporalBlend"

            HLSLPROGRAM
                #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
                #include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

                CBUFFER_START(TemporalBlendData)
                    float4 _BlendSampleOffset;  // (x, y, 1 / x, 1 / y)
                    float _TargetFrameDelta;
                    float _FrameIndex;
                CBUFFER_END

                half4 BlendFrag(Varyings input) : SV_Target
                {
                    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                    // uv is exactly on input pixel center (x + 0.5, y + 0.5)
                    float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);
                    // uv += (_BlendSampleOffset.xy * _BlitTexture_TexelSize.xy) * _FrameIndex;
                    half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);

                    float interlace = max(floor((_BlitTexture_TexelSize.z * uv.x) * _BlendSampleOffset.z + _FrameIndex) % 2, floor((_BlitTexture_TexelSize.w * uv.y) * _BlendSampleOffset.w + _FrameIndex) % 2);

	                float ftRatio = saturate(unity_DeltaTime.x * _TargetFrameDelta);
	                color.a = interlace;
                    return color;
                }

            ENDHLSL
        }
    }
}
