// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

using UnityEngine;

namespace OceanResearch
{
    /// <summary>
    /// Sets shader parameters for each geometry tile/chunk.
    /// </summary>
    public class OceanChunkRenderer : MonoBehaviour
    {
        int _lodIndex = -1;
        int _totalLodCount = -1;
        float _baseVertDensity = 32f;
        Renderer _thisRend;

        void Start()
        {
            _thisRend = GetComponent<Renderer>();
        }

        // Called when visible to a camera
        void OnWillRenderObject()
        {
            // per instance data

            // blend closest geometry in/out to avoid pop
            float meshScaleLerp = _lodIndex == 0 ? OceanRenderer.Instance.ViewerAltitudeLevelAlpha : 0f;
            // blend furthest normals scale in/out to avoid pop
            float farNormalsWeight = _lodIndex == _totalLodCount - 1 ? OceanRenderer.Instance.ViewerAltitudeLevelAlpha : 1f;
            _thisRend.material.SetVector( "_InstanceData", new Vector4( meshScaleLerp, farNormalsWeight, _lodIndex ) );

            // geometry data
            float squareSize = Mathf.Abs( transform.lossyScale.x ) / _baseVertDensity;
            float normalScrollSpeed0 = Mathf.Log( 1f + 2f * squareSize ) * 1.875f;
            float normalScrollSpeed1 = Mathf.Log( 1f + 4f * squareSize ) * 1.875f;
            _thisRend.material.SetVector( "_GeomData", new Vector4( squareSize, normalScrollSpeed0, normalScrollSpeed1, _baseVertDensity ) );

            // assign shape textures to shader
            // this relies on the render textures being init'd in CreateAssignRenderTexture::Awake().
            Camera[] shapeCams = OceanRenderer.Instance.Builder._shapeCameras;
            WaveDataCam wdc0 = shapeCams[_lodIndex].GetComponent<WaveDataCam>();
            wdc0.ApplyMaterialParams( 0, _thisRend.material );
            WaveDataCam wdc1 = (_lodIndex + 1) < shapeCams.Length ? shapeCams[_lodIndex + 1].GetComponent<WaveDataCam>() : null;
            if( wdc1 )
            {
                wdc1.ApplyMaterialParams( 1, _thisRend.material );
            }
            else
            {
                _thisRend.material.SetTexture( "_WD_Sampler_1", null );
            }
        }

        public void SetInstanceData( int lodIndex, int totalLodCount, float baseVertDensity )
        {
            _lodIndex = lodIndex; _totalLodCount = totalLodCount; _baseVertDensity = baseVertDensity;
        }
    }
}
