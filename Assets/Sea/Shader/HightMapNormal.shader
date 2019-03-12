Shader "Unlit/HightMapNormal"
{
    Properties
    {
        _Color("Tint color", Color) = (1, 1, 1, 1)
        _MainTex("Texture", 2D) = "white" {}
        _ParallaxMap("Parallax Map", 2D) = "gray" {}
        _WaveSize ("WaveSize", Range(0,20.0)) = 10.0
        _Shininess ("Shininess", Range(0,10.0)) = 10.0
        _CausticsDensity ("CausticsDensity", Range(0,10.0)) = 1.0
        _Refraction ("Refraction", Range(0,3.0)) = 1.0
        _Diffuse ("Diffuse", Range(0,2.0)) = 0.5
        
        _WaveSpeed ("WaveSpeed", Range(0,50.0)) = 30
        _WaveAmp ("WaveAmp", Range(0,1)) = 0.5
        _NoiseTex("NoiseTex", 2D) = "white" {}
        
        _EdgeColor("EdgeColor", Color) = (1, 1, 1, 1)
        _DepthFactor("DepthFactor", float) = 1.0
        
        _EmissionMap ("Emission Map", 2D) = "black" {}
        [HDR] _EmissionColor ("Emission Color", Color) = (0,0,0)
    }

        SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }
        LOD 100
        
        //屈折歪み)
        GrabPass { }

        Pass
        {
            Tags { "LightMode"="ForwardBase"}
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float2 texcoord : TEXCOORD1;
                float3 normal   : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 uvgrab : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
                float4 screenPos : TEXCOORD3;
            };

            sampler2D _MainTex;
            sampler2D _ParallaxMap;
            sampler2D _GrabTexture;
            float4 _MainTex_ST;
            fixed4 _Color;

            float2 _ParallaxMap_TexelSize;
            float _WaveSize;
            half _Shininess;
            half _CausticsDensity;
            half _Refraction;
            half _Diffuse;
            
            float _WaveSpeed;
            float _WaveAmp;
            sampler2D _NoiseTex;
            
            sampler2D _CameraDepthTexture;
            
            fixed4 _EdgeColor;
            float _DepthFactor;
            
            sampler2D _EmissionMap;
            fixed4 _EmissionColor;

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(UNITY_MATRIX_MV, v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                
                #if UNITY_UV_STARTS_AT_TOP
                float scale = -1.0;
                #else
                float scale = 1.0;
                #endif
                //テクスチャ座標を計算
                //オブジェクトのある位置を元に「後ろの映像のテクスチャ」のUV座標を算出
                o.uvgrab.xy = (float2(o.vertex.x, o.vertex.y * scale) + o.vertex.w) * 0.5;//オブジェクトの後ろ側のテクスチャの色を適切にフェッチするために正規化
                o.uvgrab.zw = o.vertex.zw;
                
                float noiseSample = tex2Dlod(_NoiseTex, float4(v.texcoord.xy, 0, 0));
                o.vertex.y += sin(_Time*_WaveSpeed*noiseSample)*_WaveAmp;
                
                // compute depth (screenPos is a float4)
                o.screenPos = ComputeScreenPos(o.vertex);
                                
                return o;
            }
            
            //動的に法線マップを計算
            //偏微分したx,zの変化を外積して算出
            fixed4 frag(v2f i) : SV_Target
            {
                //テクセルの「ひとつ隣（シフト）」分の値を計算する
                //偏微分の尺度,WaveSizeが大きいと、粗い波ができる
                float2 shiftX = float2(_ParallaxMap_TexelSize.x, 0) * _WaveSize;
                float2 shiftZ = float2(0, _ParallaxMap_TexelSize.y) * _WaveSize;
                
                //現在計算中のテクセルの上下左右の隣のテクセルを取得
                //テクセル座標:-1~1、uv座標0~1＠uv座標→ST座標に変換する必要あり
                //色情報のR値を基準に、パワーを決めている
                float3 texX = tex2D(_ParallaxMap, float4(i.uv.xy + shiftX, 0, 0)) * 2.0 - 1;
                float3 texx = tex2D(_ParallaxMap, float4(i.uv.xy - shiftX, 0, 0)) * 2.0 - 1;
                float3 texZ = tex2D(_ParallaxMap, float4(i.uv.xy + shiftZ, 0, 0)) * 2.0 - 1;
                float3 texz = tex2D(_ParallaxMap, float4(i.uv.xy - shiftZ, 0, 0)) * 2.0 - 1;
                
                // 偏微分により接ベクトルを求める
                float3 du = float3(1, (texX.x - texx.x) * _CausticsDensity, 0);
                float3 dv = float3(0, (texZ.x - texz.x) * _CausticsDensity, 1);
                
                //接ベクトルの法線を算出
                float3 n = normalize(cross(dv, du));
                
                //オフセットのようなモノ
                i.uvgrab.xy += n * i.uvgrab.z * _Refraction;//バンプマップによる裏背景の歪み
                
                //該当オブジェクトにテクスチャを投影するような形でテクセルをフェッチ
                fixed4 col = tex2Dproj(_GrabTexture, UNITY_PROJ_COORD(i.uvgrab)) * _Color;
                
                ////ライティング
                float3 lightDir = normalize(UnityWorldSpaceLightDir(i.worldPos));
                float diff = max(0, dot(n, lightDir)) + _Diffuse;//_Diffuseは裏側のオブジェクトみえる用の調整
                col *= diff;//拡散光
                
                float3 viewDir =  normalize(UnityWorldSpaceViewDir( i.worldPos ));
                float NdotL = dot(n, lightDir);
                float3 refDir = -lightDir + (2.0 * n * NdotL);//フォン鏡面反射モデル
                float spec = pow(max(0, dot(viewDir, refDir)), _Shininess);//反射光
                col += spec + unity_AmbientSky + tex2D(_EmissionMap, i.uv) * _EmissionColor;
                
                float4 depthSample = SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, i.screenPos);
                float depth = LinearEyeDepth(depthSample).r;

                float foamLine = 1 - saturate(_DepthFactor * (depth - i.screenPos.w));
                col +=  foamLine * _EdgeColor;
                
                return col;
            }
            ENDCG
        }
    }
}
