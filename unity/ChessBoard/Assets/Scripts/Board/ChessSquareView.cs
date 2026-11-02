using StillChess.Board.Core;
using UnityEngine;

namespace StillChess.Board.Board
{
    /// <summary>
    /// Lightweight component attached to each generated board tile (<c>Square_a1</c> .. <c>Square_h8</c>)
    /// to support fast raycast lookup and highlight state restoration.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class ChessSquareView : MonoBehaviour
    {
        [SerializeField] private int file;
        [SerializeField] private int rank;
        [SerializeField] private string algebraic;
        [SerializeField] private bool isLightSquare;

        private MeshRenderer _meshRenderer;
        private Material _defaultMaterial;

        public SquareCoord Coordinate => new SquareCoord(file, rank);
        public string Algebraic => algebraic;
        public bool IsLightSquare => isLightSquare;

        public void Initialize(SquareCoord coord, MeshRenderer meshRenderer, Material defaultMaterial)
        {
            file = coord.File;
            rank = coord.Rank;
            algebraic = coord.Algebraic;
            isLightSquare = coord.IsLightSquare;
            _meshRenderer = meshRenderer;
            _defaultMaterial = defaultMaterial;
            _meshRenderer.sharedMaterial = defaultMaterial;
        }

        public void SetHighlightMaterial(Material highlightMaterial)
        {
            if (_meshRenderer == null)
            {
                _meshRenderer = GetComponent<MeshRenderer>();
            }

            if (_meshRenderer != null)
            {
                _meshRenderer.sharedMaterial = highlightMaterial != null ? highlightMaterial : _defaultMaterial;
            }
        }

        public void ResetMaterial() => SetHighlightMaterial(null);
    }
}

