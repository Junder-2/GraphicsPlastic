Shader "Hidden/Universal Render Pipeline/RayReflectionBlur"
{
    HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/DynamicScalingClamping.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
        #include_with_pragmas "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRenderingKeywords.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRendering.hlsl"

        #define DUAL_MULTIPLIER 4.0
        #define GAUSSIAN_MULTIPLIER 1.0

        half4 EncodeHDR(half3 color)
        {
        #if UNITY_COLORSPACE_GAMMA
            color = sqrt(color); // linear to γ
        #endif

            return half4(color, 1.0);
        }

        half3 DecodeHDR(half4 data)
        {
            half3 color = data.xyz;

        #if UNITY_COLORSPACE_GAMMA
            color *= color; // γ to linear
        #endif

            return color;
        }

        half3 SampleHDR(float2 uv,  float2 offset)
        {
            float2 texelSize = _BlitTexture_TexelSize.xy;
            return DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv - offset * texelSize, texelSize)));
        }

        half4 FragBlurH(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 texelSize = _BlitTexture_TexelSize.xy * 2.0;
            float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

            // 9-tap gaussian blur on the downsampled source
            half3 c0 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv - float2(GAUSSIAN_MULTIPLIER * texelSize.x * 4.0, 0.0), texelSize)));
            half3 c1 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv - float2(GAUSSIAN_MULTIPLIER * texelSize.x * 3.0, 0.0), texelSize)));
            half3 c2 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv - float2(GAUSSIAN_MULTIPLIER * texelSize.x * 2.0, 0.0), texelSize)));
            half3 c3 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv - float2(GAUSSIAN_MULTIPLIER * texelSize.x * 1.0, 0.0), texelSize)));
            half3 c4 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv                                 , texelSize)));
            half3 c5 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv + float2(GAUSSIAN_MULTIPLIER * texelSize.x * 1.0, 0.0), texelSize)));
            half3 c6 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv + float2(GAUSSIAN_MULTIPLIER * texelSize.x * 2.0, 0.0), texelSize)));
            half3 c7 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv + float2(GAUSSIAN_MULTIPLIER * texelSize.x * 3.0, 0.0), texelSize)));
            half3 c8 = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampUVForBilinear(uv + float2(GAUSSIAN_MULTIPLIER * texelSize.x * 4.0, 0.0), texelSize)));

            half3 color = c0 * 0.01621622 + c1 * 0.05405405 + c2 * 0.12162162 + c3 * 0.19459459
                        + c4 * 0.22702703
                        + c5 * 0.19459459 + c6 * 0.12162162 + c7 * 0.05405405 + c8 * 0.01621622;

            return EncodeHDR(color);
        }

        half4 FragBlurV(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 texelSize = _BlitTexture_TexelSize.xy;
            float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

            // Optimized bilinear 5-tap gaussian on the same-sized source (9-tap equivalent)
            half3 c0 = SampleHDR(uv, -float2(0.0, 3.23076923) * GAUSSIAN_MULTIPLIER);
            half3 c1 = SampleHDR(uv, -float2(0.0, 1.38461538) * GAUSSIAN_MULTIPLIER);
            half3 c2 = SampleHDR(uv,  float2(0.0, 0.0) * GAUSSIAN_MULTIPLIER);
            half3 c3 = SampleHDR(uv, +float2(0.0, 1.38461538) * GAUSSIAN_MULTIPLIER);
            half3 c4 = SampleHDR(uv, +float2(0.0, 3.23076923) * GAUSSIAN_MULTIPLIER);

            half3 color = c0 * 0.07027027 + c1 * 0.31621622
                        + c2 * 0.22702703
                        + c3 * 0.31621622 + c4 * 0.07027027;

            return EncodeHDR(color);
        }

        half4 FragDualDownsample(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

            half3 c0 = SampleHDR(uv, float2(0, 0));

            half3 c1 = SampleHDR(uv, float2( DUAL_MULTIPLIER,  DUAL_MULTIPLIER));
            half3 c2 = SampleHDR(uv, float2(-DUAL_MULTIPLIER,  DUAL_MULTIPLIER));
            half3 c3 = SampleHDR(uv, float2(-DUAL_MULTIPLIER, -DUAL_MULTIPLIER));
            half3 c4 = SampleHDR(uv, float2( DUAL_MULTIPLIER, -DUAL_MULTIPLIER));

            half3 color = (1.0 / 8.0) * (c0 * 4.0 + c1 + c2 + c3 + c4);

            return EncodeHDR(color);
        }


    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass // 0
        {
            Name "Blur Horizontal"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragBlurH
            ENDHLSL
        }

        Pass // 1
        {
            Name "Blur Vertical"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragBlurV
            ENDHLSL
        }

        Pass // 2
        {
            Name "Blur Dual Downsample"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragDualDownsample
            ENDHLSL
        }
    }
}
