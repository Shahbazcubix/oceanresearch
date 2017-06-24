// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.

// Sky shader adapted from: Cloud Ten Shadertoy by nimitz: https://www.shadertoy.com/view/XtS3DD

// Put in skybox form with the help from a shader posted by 'rea' in this unity3d forum thread:
// https://forum.unity3d.com/threads/unity-5-beta-13-procedural-skybox-shader.280157/

Shader "Ocean/Sky Box" {

	SubShader
	{
		Tags{ "Queue" = "Background" "RenderType" = "Background" "PreviewType" = "Skybox" }
		Cull Off ZWrite Off

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"
			#include "Lighting.cginc"

			uniform half _HdrExposure = 1.0;

			struct appdata_t
			{
				float4 vertex : POSITION;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				half3 rayDir : TEXCOORD0;    // Vector for incoming ray, normalized ( == -eyeRay )
			};

			v2f vert( appdata_t v )
			{
				v2f OUT;
				OUT.pos = UnityObjectToClipPos( v.vertex );

				// Get the ray from the camera to the vertex and its length (which is the far point of the ray passing through the atmosphere)
				float3 eyeRay = ( mul( (float3x3)unity_ObjectToWorld, v.vertex.xyz ) );

				OUT.rayDir = half3(eyeRay);

				return OUT;
			}


			#define SUN_DIR float3(-0.70710678,0.2,-.70710678)
			float3 bgSkyColor( float3 rd )
			{
				rd.y = max( rd.y, 0. );

				float3 col = (float3)0.;

				// horizon
				float3 hor = (float3)0.;
				float hort = 1. - clamp( abs( rd.y ), 0., 1. );
				hor += 0.5*float3(.99, .5, .0)*exp2( hort*8. - 8. );
				hor += 0.1*float3(.5, .9, 1.)*exp2( hort*3. - 3. );
				hor += 0.55*float3(.6, .6, .9); //*exp2(hort*1.-1.);
				col += hor;

				// sun
				float sun = clamp( dot( SUN_DIR, rd ), 0.0, 1.0 );
				col += .2*float3(1.0, 0.3, 0.2)*pow( sun, 2.0 );
				col += .5*float3(1., .9, .9)*exp2( sun*650. - 650. );
				col += .1*float3(1., 1., 0.1)*exp2( sun*100. - 100. );
				col += .3*float3(1., .7, 0.)*exp2( sun*50. - 50. );
				col += .5*float3(1., 0.3, 0.05)*exp2( sun*10. - 10. );

				return col;
			}

			half4 frag( v2f IN ) : SV_Target
			{
				half3 col = bgSkyColor( normalize( IN.rayDir ) );
			
				// this appears to be necessary to get a smooth result, not sure why..
				col = smoothstep( 0., 1., col ); // Contrast

				return half4(col,1.0);
			}

			ENDCG
		}
	}

	Fallback Off
}
