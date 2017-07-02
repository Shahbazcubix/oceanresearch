// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

Shader "Ocean/Ocean"
{
	Properties
	{
		_Normals ( "Normals", 2D ) = "bump" {}
		_Skybox ("Skybox", CUBE) = "" {}
		_Diffuse ("Diffuse", Color) = (0.2, 0.05, 0.05, 1.0)
		_FoamTexture ( "Foam Texture", 2D ) = "white" {}
		_FoamWhiteColor("White Foam Color", Color) = (1.0, 1.0, 1.0, 1.0)
		_FoamBubbleColor ( "Bubble Foam Color", Color ) = (0.0, 0.0904, 0.105, 1.0)
	}

	Category
	{
		Tags {}

		SubShader
		{
			Pass
			{
				Name "BASE"
				Tags { "LightMode" = "Always" }
			
				CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag
				#pragma multi_compile_fog
				#include "UnityCG.cginc"

				// tints the output color based on which shape texture(s) were sampled, blended according to weight
				//#define DEBUG_SHAPE_SAMPLE

				struct appdata_t
				{
					float4 vertex : POSITION;
					float2 texcoord: TEXCOORD0;
				};

				struct v2f
				{
					float4 vertex : SV_POSITION;
					float3 n : TEXCOORD1;
					float2 foamAmount_lodAlpha : TEXCOORD5;
					float3 worldPos : TEXCOORD7;
					float2 worldXZUndisplaced : TEXCOORD9;
					
					#if defined( DEBUG_SHAPE_SAMPLE )
					float3 debugtint : TEXCOORD8;
					#endif

					UNITY_FOG_COORDS( 3 )
				};

				// GLOBAL PARAMS

				// shape data
				// Params: float3(texel size, texture resolution, shape weight multiplier)
				#define SHAPE_LOD_PARAMS(LODNUM) \
					uniform sampler2D _WD_Sampler_##LODNUM; \
					uniform float3 _WD_Params_##LODNUM; \
					uniform float2 _WD_Pos_##LODNUM; \
					uniform float2 _WD_Pos_Cont_##LODNUM;

				SHAPE_LOD_PARAMS( 0 )
				SHAPE_LOD_PARAMS( 1 )
				SHAPE_LOD_PARAMS( 2 )
				SHAPE_LOD_PARAMS( 3 )
				SHAPE_LOD_PARAMS( 4 )

				uniform float3 _OceanCenterPosWorld;
				uniform float _EnableSmoothLODs = 1.0;
				uniform float _MyTime;

				// INSTANCE PARAMS

				// Geometry data
				// x: A square is formed by 2 triangles in the mesh. Here x is square size
				// yz: normalScrollSpeed0, normalScrollSpeed1
				// w: Geometry density - side length of patch measured in squares
				uniform float4 _GeomData = float4(1.0, 1.0, 1.0, 32.0);

				// MeshScaleLerp, FarNormalsWeight, LODIndex (debug), unused
				uniform float4 _InstanceData = float4(1.0, 1.0, 0.0, 0.0 );

				#define COLOR_COUNT 5.

				// sample wave or terrain height, with smooth blend towards edges.
				// would equally apply to heights instead of displacements.
				// this could be optimized further.
				void SampleDisplacements( in sampler2D i_dispSampler, in float2 i_centerPos, in float2 i_centerPosCont, in float i_res, in float i_texelSize, in float i_geomSquareSize, in float2 i_samplePos, out float3 o_disp, out float3 o_n, out float o_wt, out float o_foamAmount )
				{
					// set the MIP based on the current square size, with the transition to the higher mip
					// hb using hte mip chain does NOT work out well when moving the shape texture around, because mip hierarchy will pop. this is knocked out below
					// and in WaveDataCam::Start()
					float4 uv = float4( (i_samplePos - i_centerPos) / (i_texelSize*i_res), 0.0, 0.0 ); //log2(SQUARE_SIZE/_WD_TexelSize_0) + frac_high );

					float2 offCont = (i_samplePos - i_centerPosCont) / (i_texelSize*i_res);
					float offContL1 = max( abs( offCont.x ), abs( offCont.y ) );

					// start fading 32 texels before the edge, wt goes to 0 within 4 texels of edge. a texel is the same
					// as a vert, and the verts are lodded out at the edges so 1 geometry square is 2 texels wide.
					o_wt = smoothstep( 0.5 - 4./i_res, .5-32./i_res, offContL1 );

					if( o_wt <= 0.001 )
					{
						o_disp = o_n = 0.;
						o_foamAmount = 0.;
						return;
					}

					uv.xy += 0.5;


					// do computations for hi-res
					o_disp = tex2Dlod( i_dispSampler, uv ).xyz;
					float3 dd = float3( i_geomSquareSize / (i_texelSize*i_res), 0.0, i_geomSquareSize );
					float3 disp_x = dd.zyy + tex2Dlod( i_dispSampler, uv + dd.xyyy ).xyz;
					float3 disp_z = dd.yyz + tex2Dlod( i_dispSampler, uv + dd.yxyy ).xyz;

					o_n = normalize( cross( disp_z - o_disp, disp_x - o_disp ) );


					// The determinant of the displacement Jacobian is a good measure for turbulence:
					// > 1: Stretch
					// < 1: Squash
					// < 0: Overlap
					float4 du = float4(disp_x.xz, disp_z.xz) - o_disp.xzxz;
					float det = (du.x * du.w - du.y * du.z) / (dd.z * dd.z);
					o_foamAmount = 1. - smoothstep(0.0, 2.0, det);
				}

				#define SAMPLE_SHAPE(LODNUM) \
					if( wt > 0. ) \
					{ \
						float3 disp_##LODNUM, n_##LODNUM; float wt_##LODNUM, foamAmount_##LODNUM; \
						SampleDisplacements( _WD_Sampler_##LODNUM, _WD_Pos_##LODNUM, _WD_Pos_Cont_##LODNUM, _WD_Params_##LODNUM.y, _WD_Params_##LODNUM.x, idealSquareSize, o.worldPos.xz, disp_##LODNUM, n_##LODNUM, wt_##LODNUM, foamAmount_##LODNUM ); \
						wt_##LODNUM *= _WD_Params_##LODNUM.z; \
						o.worldPos += wt * wt_##LODNUM * disp_##LODNUM; \
						o.n.xz += wt * wt_##LODNUM * n_##LODNUM.xz; \
						o.foamAmount_lodAlpha.x += wt * wt_##LODNUM * foamAmount_##LODNUM; \
						wt *= (1. - wt_##LODNUM); \
						debugtint = lerp( debugtint, tintCols[##LODNUM], wt ); \
					}


				v2f vert( appdata_t v )
				{
					v2f o;

					// see comments above on _GeomData
					const float SQUARE_SIZE = _GeomData.x, SQUARE_SIZE_4 = 4.0*_GeomData.x;
					const float DENSITY = _GeomData.w;

					// move to world
					o.worldPos = mul( unity_ObjectToWorld, v.vertex );
	
					// snap the verts to the grid
					// The snap size should be twice the original size to keep the shape of the eight triangles (otherwise the edge layout changes).
					o.worldPos.xz -= fmod( _OceanCenterPosWorld.xz, 2.0*SQUARE_SIZE ); // this uses hlsl fmod, not glsl mod (sign is different).
	
					// how far are we into the current LOD? compute by comparing the desired square size with the actual square size
					float2 offsetFromCenter = float2( abs( o.worldPos.x - _OceanCenterPosWorld.x ), abs( o.worldPos.z - _OceanCenterPosWorld.z ) );
					float l1norm = max( offsetFromCenter.x, offsetFromCenter.y );
					float idealSquareSize = l1norm / DENSITY;
					// this is to address numerical issues with the normal (errors are very visible at close ups of specular highlights).
					// i original had this max( .., SQUARE_SIZE ) but there were still numerical issues and a pop when changing camera height.
					// .5 was the lowest i could go before i started to see error. this needs more investigation.
					idealSquareSize = max( idealSquareSize, .5 );

					// interpolation factor to lower density (higher sampling period)
					float frac_high = idealSquareSize/SQUARE_SIZE - 1.0;
					// remap so that there is a large area of 1 weight and 0 weight for the overlaps. the overlaps
					// are significant when there are two additional strips added to every patch, so this has to
					// be conservative. if in doubt, watch a set of verts in the scene view while the camera moves.
					// there should never be any visible pop. move the camera backwards and forwards and study transitions
					// at both leading and trailing sides of motion
					const float BLACK_POINT = .15;
					const float WHITE_POINT = .8;
					frac_high = max( (frac_high - BLACK_POINT) / (WHITE_POINT-BLACK_POINT), 0. );
					const float meshScaleLerp = _InstanceData.x;
					frac_high = min( frac_high + meshScaleLerp, 1. );

					// now smoothly transition vert layouts between lod levels
					float2 m = frac( o.worldPos.xz / SQUARE_SIZE_4 ); // this always returns positive
					float2 offset = m - 0.5;
					// check if vert is within one square from the center point which the verts move towards
					float minRadius = 0.26 *_EnableSmoothLODs; //0.26 is 0.25 plus a small "epsilon" - should solve numerical issues
					if( abs( offset.x ) < minRadius ) o.worldPos.x += offset.x * frac_high * SQUARE_SIZE_4;
					if( abs( offset.y ) < minRadius ) o.worldPos.z += offset.y * frac_high * SQUARE_SIZE_4;
	

					// sample shape textures (all of them for now, but theoretically should only ever need to sample 2 of them)
					o.n = float3(0., 1., 0.);
					o.foamAmount_lodAlpha.x = 0.;
					o.worldXZUndisplaced = o.worldPos.xz;

					float3 debugtint = (float3)0.;
					float3 tintCols[5];
					tintCols[0] = float3(1., 0., 0.); tintCols[1] = float3(1., 1., 0.); tintCols[2] = float3(0., 1., 0.); tintCols[3] = float3(0., 1., 1.); tintCols[4] = float3(0., 0., 1.);

					float wt = 1.;
					SAMPLE_SHAPE( 0 );
					SAMPLE_SHAPE( 1 );
					SAMPLE_SHAPE( 2 );
					SAMPLE_SHAPE( 3 );
					SAMPLE_SHAPE( 4 );

					#if defined( DEBUG_SHAPE_SAMPLE )
					o.debugtint = debugtint;
					#endif

					// view-projection	
					o.vertex = mul( UNITY_MATRIX_VP, float4(o.worldPos,1.) );

					// used to blend normals in the fragment shader
					o.foamAmount_lodAlpha.y = frac_high;

					UNITY_TRANSFER_FOG(o,o.vertex);

					return o;
				}

				uniform float4 _Diffuse;
				uniform sampler2D _Normals;
				samplerCUBE _Skybox;
				sampler2D _FoamTexture;
				float4 _FoamWhiteColor;
				float4 _FoamBubbleColor;

				half4 frag(v2f i) : SV_Target
				{
					// normal - geom + normal mapping
					const float2 v0 = float2(0.94,0.34), v1 = float2(-0.85,-0.53);
					const float geomSquareSize = _GeomData.x;
					float nstretch = 80.*geomSquareSize; // normals scaled with geometry
					const float spdmulL = _GeomData.y;
					float2 norm = 
						tex2D( _Normals, (v0*_MyTime*spdmulL + i.worldPos.xz) / nstretch ).wz +
						tex2D( _Normals, (v1*_MyTime*spdmulL + i.worldPos.xz) / nstretch ).wz;

					// blend in next higher scale of normals to obtain continuity
					const float farNormalsWeight = _InstanceData.y;
					const float nblend = i.foamAmount_lodAlpha.y * farNormalsWeight;
					if( nblend > 0.001 )
					{
						// next lod level
						nstretch *= 2.;
						const float spdmulH = _GeomData.z;
						norm = lerp( norm,
							tex2D( _Normals, (v0*_MyTime*spdmulH + i.worldPos.xz) / nstretch ).wz +
							tex2D( _Normals, (v1*_MyTime*spdmulH + i.worldPos.xz) / nstretch ).wz,
							nblend );
					}
					
					float3 n = i.n;
					// modify geom normal with result from normal maps. -1 because we did not subtract 0.5 when sampling
					// normal maps above
					n.xz -= 0.25 * (norm - 1.0);
					n.y = 1.;
					n = normalize( n );

					// shading
					half4 col = (half4)0.;
	
					// Diffuse color
					col = _Diffuse;

					// fresnel / reflection
					float3 view = normalize( _WorldSpaceCameraPos - i.worldPos );
					float3 skyColor = texCUBE(_Skybox, reflect(-view, n) );
					col.xyz = lerp( col.xyz, skyColor, pow( 1. - max( 0., dot( view, n ) ), 8. ) );

					// Foam
					float foamAmount = i.foamAmount_lodAlpha.x;

					// Give the foam some texture
					float2 foamUV = i.worldXZUndisplaced / 80.;
					foamUV += 0.02 * n.xz;
					float foamTexValue = tex2D(_FoamTexture, foamUV).r;

					// Additive underwater foam
					float bubbleFoam = smoothstep(0.0, 0.5, foamAmount * foamTexValue);
					col.xyz += bubbleFoam * _FoamBubbleColor.rgb * _FoamBubbleColor.a;
					
					// White foam on top, with black-point fading
					float whiteFoam = foamTexValue * smoothstep(1.0 - foamAmount, 1.3 - foamAmount, foamTexValue);
					col.xyz = lerp( col.xyz, _FoamWhiteColor, whiteFoam * _FoamWhiteColor.a );

					// Fog
					UNITY_APPLY_FOG(i.fogCoord, col);
	
					//const float lodIndex = _InstanceData.z;
					//if( lodIndex == 0. )
					//	col.rgb = float3(1., 0.2, 0.2);
					//else if( lodIndex == 1. )
					//	col.rgb = float3(1., 1., 0.2);
					//else if( lodIndex == 2. )
					//	col.rgb = float3(0.2, 1., 0.2);
					//else //if( lodIndex == 3. )
					//	col.rgb = float3(0., 0.5, 1.);

					#if defined( DEBUG_SHAPE_SAMPLE )
					col.rgb *= 2.*i.debugtint;
					#endif

					// check normals
					//col.rb = norm;
					//col.g = i.facing.z;
					//col.rb *= 50.;

					return col;
				}

				ENDCG
			}
		}
	}
}
