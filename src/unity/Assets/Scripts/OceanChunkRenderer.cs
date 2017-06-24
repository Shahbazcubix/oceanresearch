// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

using UnityEngine;

namespace OceanResearch
{

    /// <summary>
    /// Sets shader parameters for each geometry tile/chunk.
    /// </summary>
    public class OceanChunkRenderer : MonoBehaviour
    {
        public int _lodIndex = -1;
        public static bool _enableSmoothLOD = true;
        public Camera[] _shapeCameras;

        [HideInInspector]
        public float _baseVertDensity = 32f;

        // debug
        public bool _regenMesh = false;

        OceanRenderer _oceanRend;
        Renderer _thisRend;

        bool _visible = false;

        void Start()
        {
            _oceanRend = GetComponentInParent<OceanRenderer>();
            _thisRend = GetComponent<Renderer>();
        }

        // script execution order ensures this executes after CircleOffset (which may be used to place the ocean in front of the camera)
        void LateUpdate()
        {
            if( _regenMesh )
            {
                _regenMesh = false;
                _oceanRend.RegenMesh();
            }

            // optimisation
            if( !_visible )
                return;


            // per instance data
            _thisRend.material.SetFloat( "_LODIndex", (float)_lodIndex );
            float scaleLerp = _lodIndex == 0 ? OceanRenderer.CAMY_MESH_SCALE_LERP : 0f;
            _thisRend.material.SetFloat( "_MeshScaleLerp", scaleLerp ); // transitions ocean based on camera height

            // global/per material data - would ideally be set just once..
            _thisRend.material.SetVector( "_OceanCenterPosWorld", _oceanRend.transform.position );
            _thisRend.material.SetFloat( "_EnableSmoothLODs", _enableSmoothLOD ? 1f : 0f ); // debug

            float squareSize = Mathf.Abs( transform.lossyScale.x ) / _baseVertDensity;
            _thisRend.material.SetVector( "_GeomData", new Vector4( squareSize, squareSize * 2f, squareSize * 4f, _baseVertDensity ) );

            // this relies on the render textures being init'd in CreateAssignRenderTexture::Awake().
            // the only reason I'm doing this here is because the assignments are lost if you edit the shader while running.
            for( int j = 0; j < _shapeCameras.Length; j++ )
                _thisRend.material.SetTexture( "_WD_Sampler_" + j.ToString(), _shapeCameras[j].targetTexture );
        }

        void OnBecameVisible()
        {
            _visible = true;
        }
        void OnBecameInvisible()
        {
            _visible = false;
        }
    }
}
