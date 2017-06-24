// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

using UnityEngine;
using System.Collections.Generic;

namespace OceanResearch
{
    /// <summary>
    /// Positions wave data render camera. Snaps to shape texels to avoid aliasing. May be combined iwth Circle Offset component to place in front of camera.
    /// </summary>
    [RequireComponent( typeof( Camera ) )]
    public class WaveDataCam : MonoBehaviour
    {
        public ShapeGerstner _gerstner;

        public int _wdRes = 0;

        public bool _autoConfigCircleOffset = true;

        string _waveDataResParamName;
        string _waveDataTexSizeParamName;
        string _waveDataPosParamName;
        string _waveDataPosContParamName;

        //bool _moveWithShape = false;
        //Vector2 _smoothPos = Vector2.zero;
        int _shapeRes = 512;

        void Start()
        {
            if( camera && camera.targetTexture )
            {
                // hb using the mip chain does NOT work out well when moving the shape texture around, because mip hierarchy will pop when the position
                // snaps. this is knocked out by the CreateAssignRenderTexture script.
                //camera.targetTexture.useMipMap = false;
                _shapeRes = camera.targetTexture.width;
            }

            _waveDataResParamName = "_WD_Res_" + _wdRes.ToString();
            _waveDataTexSizeParamName = "_WD_TexelSize_" + _wdRes.ToString();
            _waveDataPosParamName = "_WD_Pos_" + _wdRes.ToString();
            _waveDataPosContParamName = "_WD_Pos_Cont_" + _wdRes.ToString();

            if( _autoConfigCircleOffset )
            {
                SphereOffset co = GetComponent<SphereOffset>();
                if( co )
                {
                    co._radius = camera.orthographicSize * 0.8f;
                }
            }

            // gather list of hte ocean chunk rends
            FindOceanRenderers();
        }

        // script execution order ensures this runs after CircleOffset
        void LateUpdate()
        {
            //if( _moveWithShape )
            //{
            //    Vector2 vel = _gerstner.m_speed * new Vector2( Mathf.Cos( Mathf.Deg2Rad * _gerstner.m_angle ), Mathf.Sin( Mathf.Deg2Rad * _gerstner.m_angle ) );

            //    _smoothPos.x += vel.x * Time.deltaTime;
            //    _smoothPos.y += vel.y * Time.deltaTime;
            //}

            // find snap period
            int width = camera.targetTexture.width;
            if( width != _shapeRes )
            {
                camera.targetTexture.Release();
                camera.targetTexture.width = camera.targetTexture.height = _shapeRes;
                camera.targetTexture.Create();
            }
            float textureRes = (float)camera.targetTexture.width;
            float texelWidth = 2f * camera.orthographicSize / textureRes;

            Vector3 continuousPos = transform.position;

            // snap so that shape texels are stationary
            transform.position = continuousPos
                - new Vector3( Mathf.Repeat( continuousPos.x, texelWidth ), 0f, Mathf.Repeat( continuousPos.z, texelWidth ) );

            // moving shape disabled for now, needs to be reconciled with position snap above
            //Vector3 pos = transform.localPosition;
            //pos.x = Mathf.Repeat( m_smoothPos.x, texelWidth );
            //pos.z = Mathf.Repeat( m_smoothPos.y, texelWidth );
            //transform.localPosition = pos;

            if( _renderers == null || _renderers.Count == 0 || _renderers[0] == null )
            {
                FindOceanRenderers();

                if( _renderers.Count == 0 || _renderers[0] == null )
                {
                    Debug.LogWarning( "No Renderer components on OceanChunkRenderers found.", this );
                }
            }

            foreach( Renderer r in _renderers )
            {
                if( !r || !r.material ) continue;

                r.material.SetFloat( _waveDataResParamName, textureRes );
                r.material.SetFloat( _waveDataTexSizeParamName, texelWidth );
                r.material.SetVector( _waveDataPosParamName, new Vector2( transform.position.x, transform.position.z ) );
                r.material.SetVector( _waveDataPosContParamName, new Vector2( continuousPos.x, continuousPos.z ) );
            }
        }

        void OnGUI()
        {
            float w = 125f;

            // see comment above
            //m_moveWithShape = GUI.Toggle( new Rect(0,50,w,25), m_moveWithShape, "Move shape" );

            float yoff = 50f * (float)_wdRes;

            // toggle to stop wave data camera moving
            SphereOffset co = GetComponent<SphereOffset>();
            if( co != null )
                co.enabled = GUI.Toggle( new Rect( 0, 100 + yoff, 15, 25 ), co.enabled, "" );

            GUI.Label( new Rect( 15, 100 + yoff, w, 25 ), _wdRes.ToString() + " shape res: " + _shapeRes );
            float res = GUI.HorizontalSlider( new Rect( 0, 125 + yoff, w, 25 ), (int)(Mathf.Log( (float)_shapeRes ) / Mathf.Log( 2f )), 5, 11 );
            res = Mathf.Pow( 2f, Mathf.Floor( res ) );
            _shapeRes = (int)res;
        }

        List<Renderer> _renderers = null;
        void FindOceanRenderers()
        {
            _renderers = new List<Renderer>();

            OceanChunkRenderer[] ocrs = FindObjectsOfType<OceanChunkRenderer>();
            foreach( var ocr in ocrs )
            {
                Renderer r = ocr.GetComponent<Renderer>();
                if( r != null )
                {
                    _renderers.Add( r );
                }
            }
        }

        Camera _camera; new Camera camera { get { return _camera != null ? _camera : (_camera = GetComponent<Camera>()); } }
    }
}
