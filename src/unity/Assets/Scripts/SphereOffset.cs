// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

using UnityEngine;

namespace OceanResearch
{
    /// <summary>
    /// Offsets this gameobject from a provided viewer.
    /// </summary>
    public class SphereOffset : MonoBehaviour
    {
        public float _radius = 2.3f;
        public Transform _viewpoint;
        public bool _heightCompensate = false;

        // the script execution order ensures this executes before WaveDataCam::LateUpdate and 
        void LateUpdate()
        {
            float thisY = transform.position.y;
            float r = _radius;

            if( _heightCompensate )
            {
                r *= Mathf.Abs( thisY - _viewpoint.position.y );
            }

            Vector3 pos = _viewpoint.position + _viewpoint.forward * r;

            // constrain on same horizontal plane as before
            pos.y = thisY;

            transform.position = pos;
        }
    }
}
