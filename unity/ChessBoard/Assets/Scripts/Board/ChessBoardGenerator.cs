using System.Collections.Generic;
using StillChess.Board.Core;
using StillChess.Board.Materials;
using UnityEngine;
using UnityEngine.Rendering;

namespace StillChess.Board.Board
{
    /// <summary>
    /// Generates an 8x8 chessboard with alternating dark (<c>a1</c>) and light (<c>b1</c>) squares,
    /// centered at the board root's origin and mapped to standard algebraic notation (<c>a1</c> through <c>h8</c>).
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class ChessBoardGenerator : MonoBehaviour
    {
        public const float DefaultSquareSize = 1.0f;
        public const float DefaultSquareThickness = 0.12f;
        public const float DefaultFrameMargin = 0.35f;

        [SerializeField] private float squareSize = DefaultSquareSize;
        [SerializeField] private float squareThickness = DefaultSquareThickness;
        [SerializeField] private float frameMargin = DefaultFrameMargin;

        private readonly Dictionary<SquareCoord, ChessSquareView> _squaresByCoord =
            new Dictionary<SquareCoord, ChessSquareView>(SquareCoord.TotalSquares);

        private Transform _squaresContainer;
        private GameObject _boardFrame;

        public float SquareSize => squareSize;
        public float SquareThickness => squareThickness;

        /// <summary>Y coordinate in board-local space where pieces rest on top of the squares.</summary>
        public float SurfaceHeight => 0.0f;

        public IReadOnlyDictionary<SquareCoord, ChessSquareView> Squares => _squaresByCoord;

        /// <summary>
        /// Builds or rebuilds the 64 squares (<c>a1..h8</c>) and surrounding border frame using shared mobile materials.
        /// </summary>
        public void GenerateBoard(MobileMaterialPalette palette)
        {
            ClearBoard();

            var containerObject = new GameObject("BoardSquares");
            _squaresContainer = containerObject.transform;
            _squaresContainer.SetParent(transform, false);
            _squaresContainer.localPosition = Vector3.zero;
            _squaresContainer.localRotation = Quaternion.identity;

            CreateBoardFrame(palette.BoardFrameMaterial);

            for (int rank = 0; rank < SquareCoord.BoardDimension; rank++)
            {
                for (int file = 0; file < SquareCoord.BoardDimension; file++)
                {
                    var coord = new SquareCoord(file, rank);
                    ChessSquareView squareView = CreateSquareTile(coord, palette);
                    _squaresByCoord[coord] = squareView;
                }
            }
        }

        public bool TryGetSquareView(SquareCoord coord, out ChessSquareView squareView) =>
            _squaresByCoord.TryGetValue(coord, out squareView);

        public bool TryGetSquareView(string algebraic, out ChessSquareView squareView)
        {
            squareView = null;
            return SquareCoord.TryParse(algebraic, out SquareCoord coord) &&
                   _squaresByCoord.TryGetValue(coord, out squareView);
        }

        public Vector3 GetSquareSurfaceLocalPosition(SquareCoord coord) =>
            coord.ToLocalPosition(squareSize, SurfaceHeight);

        public void ClearHighlights()
        {
            foreach (ChessSquareView square in _squaresByCoord.Values)
            {
                if (square != null)
                {
                    square.ResetMaterial();
                }
            }
        }

        public void ClearBoard()
        {
            _squaresByCoord.Clear();

            if (_squaresContainer != null)
            {
                DestroyObjectSafe(_squaresContainer.gameObject);
                _squaresContainer = null;
            }
            else
            {
                Transform existing = transform.Find("BoardSquares");
                if (existing != null)
                {
                    DestroyObjectSafe(existing.gameObject);
                }
            }

            if (_boardFrame != null)
            {
                DestroyObjectSafe(_boardFrame);
                _boardFrame = null;
            }
            else
            {
                Transform existingFrame = transform.Find("BoardFrame");
                if (existingFrame != null)
                {
                    DestroyObjectSafe(existingFrame.gameObject);
                }
            }
        }

        private ChessSquareView CreateSquareTile(SquareCoord coord, MobileMaterialPalette palette)
        {
            GameObject tile = GameObject.CreatePrimitive(PrimitiveType.Cube);
            tile.name = $"Square_{coord.Algebraic}";
            tile.isStatic = true;

            Transform tileTransform = tile.transform;
            tileTransform.SetParent(_squaresContainer, false);
            tileTransform.localScale = new Vector3(squareSize, squareThickness, squareSize);
            tileTransform.localPosition = coord.ToLocalPosition(squareSize, -squareThickness * 0.5f);
            tileTransform.localRotation = Quaternion.identity;

            var meshRenderer = tile.GetComponent<MeshRenderer>();
            meshRenderer.shadowCastingMode = ShadowCastingMode.Off;
            meshRenderer.receiveShadows = true;
            meshRenderer.lightProbeUsage = LightProbeUsage.Off;
            meshRenderer.reflectionProbeUsage = ReflectionProbeUsage.Off;

            Material squareMaterial = palette.GetSquareMaterial(coord);
            var squareView = tile.AddComponent<ChessSquareView>();
            squareView.Initialize(coord, meshRenderer, squareMaterial);

            return squareView;
        }

        private void CreateBoardFrame(Material frameMaterial)
        {
            _boardFrame = GameObject.CreatePrimitive(PrimitiveType.Cube);
            _boardFrame.name = "BoardFrame";
            _boardFrame.isStatic = true;

            Collider frameCollider = _boardFrame.GetComponent<Collider>();
            if (frameCollider != null)
            {
                DestroyObjectSafe(frameCollider);
            }

            float boardSpan = SquareCoord.BoardDimension * squareSize;
            float frameSpan = boardSpan + (frameMargin * 2.0f);
            float frameThickness = squareThickness * 1.15f;

            Transform frameTransform = _boardFrame.transform;
            frameTransform.SetParent(transform, false);
            frameTransform.localScale = new Vector3(frameSpan, frameThickness, frameSpan);
            frameTransform.localPosition = new Vector3(0.0f, -(frameThickness * 0.5f) - 0.01f, 0.0f);
            frameTransform.localRotation = Quaternion.identity;

            var renderer = _boardFrame.GetComponent<MeshRenderer>();
            renderer.sharedMaterial = frameMaterial;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            renderer.receiveShadows = true;
            renderer.lightProbeUsage = LightProbeUsage.Off;
            renderer.reflectionProbeUsage = ReflectionProbeUsage.Off;
        }

        private static void DestroyObjectSafe(UnityEngine.Object obj)
        {
            if (obj == null)
            {
                return;
            }

            if (Application.isPlaying)
            {
                Destroy(obj);
            }
            else
            {
                DestroyImmediate(obj);
            }
        }
    }
}

