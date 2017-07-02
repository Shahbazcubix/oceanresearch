// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

using UnityEngine;

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

        struct RenderData
        {
            public float _texelWidth;
            public float _textureRes;
            public Vector3 _posContinuous;
            public Vector3 _posSnapped;
        }
        RenderData _renderData = new RenderData();

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
            _renderData._textureRes = (float)camera.targetTexture.width;
            _renderData._texelWidth = 2f * camera.orthographicSize / _renderData._textureRes;
            // snap so that shape texels are stationary
            _renderData._posContinuous = transform.position;
            _renderData._posSnapped = _renderData._posContinuous
                - new Vector3( Mathf.Repeat( _renderData._posContinuous.x, _renderData._texelWidth ), 0f, Mathf.Repeat( _renderData._posContinuous.z, _renderData._texelWidth ) );

            // set projection matrix to snap to texels
            camera.ResetProjectionMatrix();
            Matrix4x4 P = camera.projectionMatrix, T = new Matrix4x4();
            T.SetTRS( new Vector3( _renderData._posContinuous.x - _renderData._posSnapped.x, _renderData._posContinuous.z - _renderData._posSnapped.z ), Quaternion.identity, Vector3.one );
            P = P * T;
            camera.projectionMatrix = P;
        }

        public void ApplyMaterialParams( int shapeSlot, Material mat )
        {
            mat.SetTexture( "_WD_Sampler_" + shapeSlot.ToString(), camera.targetTexture );
            float shapeWeight = _biggestLod ? OceanRenderer.Instance.ViewerAltitudeLevelAlpha : 1f;
            mat.SetVector( "_WD_Params_" + shapeSlot.ToString(), new Vector3( _renderData._texelWidth, _renderData._textureRes, shapeWeight ) );
            mat.SetVector( "_WD_Pos_" + shapeSlot.ToString(), new Vector2( _renderData._posSnapped.x, _renderData._posSnapped.z ) );
            mat.SetVector( "_WD_Pos_Cont_" + shapeSlot.ToString(), new Vector2( _renderData._posContinuous.x, _renderData._posContinuous.z ) );
            mat.SetInt( "_WD_LodIdx_" + shapeSlot.ToString(), _wdRes );
        }

        void OnGUI()
        {
            float w = 125f;

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

        Camera _camera; new Camera camera { get { return _camera != null ? _camera : (_camera = GetComponent<Camera>()); } }
    }
}
