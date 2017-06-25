// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

Shader "Ocean/Ocean"
{
	Properties
	{
		_RefractAmt  ("Refract Strengh", range (0,1)) = 0
		_Normals ( "Normals", 2D ) = "bump" {}
		_Skybox ("Skybox", CUBE) = "" {}
		_Diffuse ("Diffuse", Color) = (0.2, 0.05, 0.05, 1.0)
	}

	Category
	{

		// We must be transparent, so other objects are drawn before this one.
		Tags { "Queue"="Transparent" "RenderType"="Opaque" }


		SubShader
		{

			// This pass grabs the screen behind the object into a texture.
			// We can access the result in the next pass as _GrabTexture
			GrabPass
			{
				Name "BASE"
				Tags { "LightMode" = "Always" }
			}
		
			// Main pass: Take the texture grabbed above and use the bumpmap to perturb it
			// on to the screen
			Pass
			{
				Name "BASE"
				Tags { "LightMode" = "Always" }
			
				CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag
				#pragma multi_compile_fog
				#include "UnityCG.cginc"

				struct appdata_t {
					float4 vertex : POSITION;
					float2 texcoord: TEXCOORD0;
				};

				struct v2f {
					float4 vertex : SV_POSITION;
					float4 uvgrab : TEXCOORD0;
					float3 n : TEXCOORD1;
					float4 facing : TEXCOORD5;
					float3 view : TEXCOORD6;
					float2 worldXZ : TEXCOORD7;
					UNITY_FOG_COORDS(3)
				};

				// shape data
				#define SHAPE_LOD_PARAMS(LODNUM) \
					uniform sampler2D _WD_Sampler_##LODNUM; \
					uniform float _WD_TexelSize_##LODNUM; \
					uniform float _WD_Res_##LODNUM; \
					uniform float2 _WD_Pos_##LODNUM; \
					uniform float2 _WD_Pos_Cont_##LODNUM;

				SHAPE_LOD_PARAMS( 0 )
				SHAPE_LOD_PARAMS( 1 )
				SHAPE_LOD_PARAMS( 2 )
				SHAPE_LOD_PARAMS( 3 )


				uniform float _RefractAmt;
				uniform float2 _TextureCenterPosXZ;
				uniform sampler2D_float _CameraDepthTexture;

				uniform sampler2D _Normals;

				// only needed for smallest lod - to lerp out lod before doubling ocean scale
				uniform float _MeshScaleLerp = 1.0;
				uniform float _IsSmallestLOD = 0.0; // 1.0 if smallest lod
				uniform float3 _OceanCenterPosWorld;

				uniform float _EnableSmoothLODs = 1.0;
				uniform float _LODIndex = 0.;

				uniform float4 _Diffuse;

				// Geometry data
				// xyz: A square is formed by 2 triangles in the mesh. Here xyz is (square size, 2 X square size, 4 X square size)
				// w: Geometry density - side length of patch measured in squares
				uniform float4 _GeomData = float4(1.0, 2.0, 4.0, 32.0);

				#define COLOR_COUNT 5.

				// sample wave or terrain height, with smooth blend towards edges.
				// would equally apply to heights instead of displacements.
				// this could be optimized further.
				void SampleDisplacements( in sampler2D i_dispSampler, in float2 i_centerPos, in float2 i_centerPosCont, in float i_res, in float i_texelSize, in float i_geomSquareSize, in float2 i_samplePos, out float3 o_disp, out float3 o_n, out float o_wt )
				{
					// set the MIP based on the current square size, with the transition to the higher mip
					// hb using hte mip chain does NOT work out well when moving the shape texture around, because mip hierarchy will pop. this is knocked out below
					// and in WaveDataCam::Start()
					float4 uv = float4( (i_samplePos - i_centerPos) / (i_texelSize*i_res), 0.0, 0.0 ); //log2(SQUARE_SIZE/_WD_TexelSize_0) + frac_high );

					float2 offCont = (i_samplePos - i_centerPosCont) / (i_texelSize*i_res);
					float offContL1 = max( abs( offCont.x ), abs( offCont.y ) );

					o_wt = smoothstep( 0.5 - 1./i_res, .5-4./i_res, offContL1 );

					if( o_wt <= 0.001 )
					{
						o_disp = o_n = 0.;
						return;
					}

					uv.xy += 0.5;


					// do computations for hi-res
					o_disp = tex2Dlod( i_dispSampler, uv ).xyz;
					float3 dd = float3( i_geomSquareSize / (i_texelSize*i_res), 0.0, i_geomSquareSize );
					float3 disp_x = dd.zyy + tex2Dlod( i_dispSampler, uv + dd.xyyy ).xyz;
					float3 disp_z = dd.yyz + tex2Dlod( i_dispSampler, uv + dd.yxyy ).xyz;

					o_n = normalize( cross( disp_z - o_disp, disp_x - o_disp ) );
				}

				#define SAMPLE_SHAPE(LODNUM) \
					if( wt > 0. ) \
					{ \
						float3 disp_##LODNUM, n_##LODNUM; float wt_##LODNUM; \
						SampleDisplacements( _WD_Sampler_##LODNUM, _WD_Pos_##LODNUM, _WD_Pos_Cont_##LODNUM, _WD_Res_##LODNUM, _WD_TexelSize_##LODNUM, idealSquareSize, pos_world.xz, disp_##LODNUM, n_##LODNUM, wt_##LODNUM ); \
						pos_world += wt * wt_##LODNUM * disp_##LODNUM; \
						o.n.xz += wt * wt_##LODNUM * n_##LODNUM.xz; \
						wt *= (1. - wt_##LODNUM); \
					}


				v2f vert( appdata_t v )
				{
					v2f o;

					// see comments above on _GeomData
					const float SQUARE_SIZE = _GeomData.x, SQUARE_SIZE_2 = _GeomData.y, SQUARE_SIZE_4 = _GeomData.z;
					const float DENSITY = _GeomData.w;

					// move to world
					float3 pos_world = mul( unity_ObjectToWorld, v.vertex );
	
					// snap the verts to the grid
					// The snap size should be twice the original size to keep the shape of the eight triangles (otherwise the edge layout changes).
					pos_world.xz -= fmod( _OceanCenterPosWorld.xz, SQUARE_SIZE_2 ); // this uses hlsl fmod, not glsl mod (sign is different).
	
					// how far are we into the current LOD? compute by comparing the desired square size with the actual square size
					float2 offsetFromCenter = float2( abs( pos_world.x - _OceanCenterPosWorld.x ), abs( pos_world.z - _OceanCenterPosWorld.z ) );
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
					frac_high = min( frac_high + _MeshScaleLerp, 1. );

					// now smoothly transition vert layouts between lod levels
					float2 m = frac( pos_world.xz / SQUARE_SIZE_4 ); // this always returns positive
					float2 offset = m - 0.5;
					// check if vert is within one square from the center point which the verts move towards
					float minRadius = 0.26 *_EnableSmoothLODs; //0.26 is 0.25 plus a small "epsilon" - should solve numerical issues
					if( abs( offset.x ) < minRadius ) pos_world.x += offset.x * frac_high * SQUARE_SIZE_4;
					if( abs( offset.y ) < minRadius ) pos_world.z += offset.y * frac_high * SQUARE_SIZE_4;
	
	
					// uv
					// set the MIP based on the current square size, with the transition to the higher mip
					// hb using hte mip chain does NOT work out well when moving the shape texture around, because mip hierarchy will pop. this is knocked out below
					// and in WaveDataCam::Start()
	
					o.n = float3(0., 1., 0.);

					float wt = 1.;
					SAMPLE_SHAPE( 0 );
					SAMPLE_SHAPE( 1 );
					SAMPLE_SHAPE( 2 );
					SAMPLE_SHAPE( 3 );


					// view-projection	
					o.vertex = mul( UNITY_MATRIX_VP, float4(pos_world,1.) );
					o.worldXZ = pos_world.xz;

					// used to scale normals in the fragment shader
					o.facing.z = SQUARE_SIZE;
					o.facing.w = frac_high;
	
					// refract starts here
	
					#if UNITY_UV_STARTS_AT_TOP
					float scale = -1.0;
					#else
					float scale = 1.0;
					#endif
					o.uvgrab.xy = (float2(o.vertex.x, o.vertex.y*scale) + o.vertex.w) * 0.5;
					o.uvgrab.zw = o.vertex.zw;
					//o.uvmain = TRANSFORM_TEX( v.texcoord, _WD_Sampler_0 );
	
					UNITY_TRANSFER_FOG(o,o.vertex);
	
					float3 V = _WorldSpaceCameraPos - pos_world.xyz;
					o.facing.y = length(V);
					o.view = V/o.facing.y;
					o.facing.x = max( dot( o.view, o.n ), 0. );
					return o;
				}

				sampler2D _GrabTexture;
				float4 _GrabTexture_TexelSize;
				sampler2D _MainTex;
				samplerCUBE _Skybox;

				#define SUN_DIR float3(-0.70710678,0.,-.70710678)

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

				half4 frag (v2f i) : SV_Target
				{
					float l = i.facing.x;
					float3 lightDir = normalize(float3(1.,.1,1.));
	
					// normal - geom + normal mapping
					float3 n = i.n;
					float th0 = .35, th1 = 3.7;
					float2 v0 = float2(cos( th0 ), sin( th0 )), v1 = float2(cos( th1 ), sin( th1 ));
					float nscale = .25;
					const bool USE_LOG_SCALE = false;
					float geomSquareSize = i.facing.z;
					float nstretch = 80.*geomSquareSize; // normals scaled with geometry
					float spdmulL = log( 1. + 2.*i.facing.z ) * 1.875;
					float2 norm = 
						nscale * (tex2D( _Normals, (v0 * _Time.y*spdmulL + i.worldXZ) / nstretch ).wz - .5) +
						nscale * (tex2D( _Normals, (v1 * _Time.y*spdmulL + i.worldXZ) / nstretch ).wz - .5);
					// blend in next higher scale of normals to obtain continuity
					float nblend = i.facing.w;
					if( nblend > 0.001 )
					{
						nstretch *= 2.;
						float spdmulH = log( 1. + 4.*i.facing.z ) * 1.875;
						norm = lerp( norm,
							nscale * (tex2D( _Normals, (v0 * _Time.y*spdmulH + i.worldXZ) / nstretch ).wz - .5) +
							nscale * (tex2D( _Normals, (v1 * _Time.y*spdmulH + i.worldXZ) / nstretch ).wz - .5),
							nblend );
					}

					n.xz -= norm;
					n.y = 1.;
					n = normalize( n );

					// shading
					half4 col = (half4)0.;
	
					// calculate perturbed coordinates
					// dz - commented, but I'll leave it in for now in case we want to go transparent
					/*
					float2 offset = -l * mul(UNITY_MATRIX_V,float4(n,0.)).xy/i.facing.y; // divide by viewz to ramp down
					float4 refractUV = i.uvgrab;
					refractUV.xy = _RefractAmt * offset * i.uvgrab.z + i.uvgrab.xy;
					col = tex2Dproj( _GrabTexture, UNITY_PROJ_COORD(refractUV));
					col.xyz = float3(0.7,.7,.7);
	
					// blue tint
					col.xyz *= float3(0.8, 0.5, 1.3) * 0.2;
					*/

					// Diffuse color
					col = _Diffuse;

					// fresnel / reflection
				//	float3 skyColor = bgSkyColor( reflect( -i.view, n ) );
					float3 skyColor = texCUBE(_Skybox, normalize( reflect(-i.view, n) ));
					col.xyz = lerp( col.xyz, skyColor, pow( 1. - max( 0., dot( i.view, n ) ), 8. ) );

					//float4 uv = i.uvgrab/i.uvgrab.w;
					//uv.y = 1. - uv.y;
					//float d = LinearEyeDepth( tex2D( _CameraDepthTexture, uv.xy ).x );
					//float transmittance = exp( -0.08 * max(0.,d-i.facing.y) ); // THIS IS WRONG - d is viewZ whereas i.facing.y is distance to surface
					//col.xyz = lerp( col.xyz, float3(.3,.7,.8), 1.-transmittance );
	
					UNITY_APPLY_FOG(i.fogCoord, col);
	
					//if( _LODIndex == 0. )
					//	col.rgb = float3(1., 0.2, 0.2);
					//else if( _LODIndex == 1. )
					//	col.rgb = float3(1., 1., 0.2);
					//else if( _LODIndex == 2. )
					//	col.rgb = float3(0.2, 1., 0.2);
					//else //if( _LODIndex == 3. )
					//	col.rgb = float3(0., 0.5, 1.);

					return col;
				}

				ENDCG
			}
		}

		// ------------------------------------------------------------------
		// Fallback for older cards and Unity non-Pro
		SubShader
		{
			Blend DstColor Zero
			Pass {
				Name "BASE"
				SetTexture [_MainTex] {	combine texture }
			}
		}
	}

}
