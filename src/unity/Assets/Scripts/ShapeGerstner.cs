// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE)

using UnityEngine;

namespace OceanResearch
{
    /// <summary>
    /// Support script for gerstner wave ocean shape.
    /// </summary>
    public class ShapeGerstner : MonoBehaviour
    {
        bool _frozen = false;
        float _elapsedTime = 0f;
        Renderer _rend;

        void Start()
        {
            _rend = GetComponent<Renderer>();
        }

        void LateUpdate()
        {
            if( !_frozen )
            {
                _elapsedTime += Time.deltaTime;
            }

            _rend.material.SetFloat( "_MyTime", _elapsedTime );
        }

        void OnGUI()
        {
            _frozen = GUI.Toggle( new Rect( 0, 75, 100, 25 ), _frozen, "Freeze waves" );
        }
    }
}
