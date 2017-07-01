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
            _thisRend.material.SetVector( "_GeomData", new Vector4( squareSize, squareSize * 2f, squareSize * 4f, _baseVertDensity ) );
        }

        public void SetInstanceData( int lodIndex, int totalLodCount, float baseVertDensity )
        {
            _lodIndex = lodIndex; _totalLodCount = totalLodCount; _baseVertDensity = baseVertDensity;
        }
    }
}
