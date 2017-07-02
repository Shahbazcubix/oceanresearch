// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

using UnityEngine;
using System.Collections.Generic;

namespace OceanResearch
{
    /// <summary>
    /// Positions wave data render camera. Snaps to shape texels to avoid aliasing. May be combined with Circle Offset component to place in front of camera.
    /// </summary>
    [RequireComponent( typeof( Camera ) )]
    public class WaveDataCam : MonoBehaviour
    {
        public int _wdRes = 0;
        public bool _biggestLod = false;

        string _waveDataPosParamName;
        string _waveDataParamsName;
        string _waveDataPosContParamName;

        int _shapeRes = 512;

        void Start()
        {
            if( camera.targetTexture )
            {
                // hb using the mip chain does NOT work out well when moving the shape texture around, because mip hierarchy will pop when the position
                // snaps. this is knocked out by the CreateAssignRenderTexture script.
                //camera.targetTexture.useMipMap = false;
                _shapeRes = camera.targetTexture.width;
            }

            camera.depthTextureMode = DepthTextureMode.None;

            _waveDataPosParamName = "_WD_Pos_" + _wdRes.ToString();
            _waveDataParamsName = "_WD_Params_" + _wdRes.ToString();
            _waveDataPosContParamName = "_WD_Pos_Cont_" + _wdRes.ToString();

            // gather list of the ocean chunk renderers
            FindOceanRenderers();
        }

        // script execution order ensures this runs after CircleOffset
        void LateUpdate()
        {
            // ensure camera size matches geometry size
            camera.orthographicSize = 2f * Mathf.Abs( transform.lossyScale.x );
            bool flip = transform.lossyScale.z < 0f;
            transform.localEulerAngles = new Vector3( flip ? -90f : 90f, 0f, 0f );

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
            // snap so that shape texels are stationary
            Vector3 continuousPos = transform.position;
            Vector3 snappedPos = continuousPos
                - new Vector3( Mathf.Repeat( continuousPos.x, texelWidth ), 0f, Mathf.Repeat( continuousPos.z, texelWidth ) );

            // set projection matrix to snap to texels
            camera.ResetProjectionMatrix();
            Matrix4x4 P = camera.projectionMatrix, T = new Matrix4x4();
            T.SetTRS( new Vector3( continuousPos.x - snappedPos.x, continuousPos.z - snappedPos.z ), Quaternion.identity, Vector3.one );
            P = P * T;
            camera.projectionMatrix = P;


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

                float shapeWeight = _biggestLod ? OceanRenderer.Instance.ViewerAltitudeLevelAlpha : 1f;
                r.material.SetVector( _waveDataParamsName, new Vector3( texelWidth, textureRes, shapeWeight ) );
                r.material.SetVector( _waveDataPosParamName, new Vector2( snappedPos.x, snappedPos.z ) );
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
