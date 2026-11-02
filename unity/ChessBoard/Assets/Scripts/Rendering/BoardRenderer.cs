using System;
using System.Collections.Generic;
using StillChess.Board.Board;
using StillChess.Board.CameraControl;
using StillChess.Board.Core;
using StillChess.Board.Materials;
using StillChess.Board.Pieces;
using UnityEngine;

namespace StillChess.Board.Rendering
{
    /// <summary>
    /// Presentation-only 3D chessboard renderer that reconstructs the 8x8 board and piece layout
    /// from authoritative six-field FEN snapshots sent by Flutter.
    /// <para>
    /// By architectural contract (<c>docs/unity_flutter_bridge.md</c>), Unity never computes legal moves,
    /// validates turns, or adjudicates game results. It renders FEN snapshots and reports square selection intents.
    /// </para>
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(ChessBoardGenerator))]
    [RequireComponent(typeof(PieceFactory))]
    public sealed class BoardRenderer : MonoBehaviour
    {
        [Serializable]
        private sealed class BridgeSnapshotCameraDto
        {
            public string orientation;
            public string preset;
        }

        [Serializable]
        private sealed class BridgeHighlightMoveDto
        {
            public string to;
            public string style;
        }

        [Serializable]
        private sealed class BridgeHighlightsDto
        {
            public string selectedSquare;
            public BridgeHighlightMoveDto[] moves;
        }

        [Serializable]
        private sealed class BridgeSnapshotPayloadDto
        {
            public string fen;
            public string selectedSquare;
            public BridgeHighlightsDto highlights;
            public BridgeSnapshotCameraDto camera;
            public bool inputEnabled;
        }

        [Serializable]
        private sealed class BridgeEnvelopeDto
        {
            public int protocolVersion;
            public string type;
            public string sessionId;
            public string gameId;
            public int revision;
            public BridgeSnapshotPayloadDto payload;
        }

        [SerializeField] private string initialFen = FenPlacementParser.StandardStartingFen;
        [SerializeField] private bool buildOnAwake = true;
        [SerializeField] private ChessCameraController cameraController;

        private readonly Dictionary<SquareCoord, ChessPieceView> _piecesBySquare =
            new Dictionary<SquareCoord, ChessPieceView>(32);

        private ChessBoardGenerator _boardGenerator;
        private PieceFactory _pieceFactory;
        private MobileMaterialPalette _materialPalette;
        private Transform _piecesContainer;

        public string CurrentFen { get; private set; } = string.Empty;
        public PieceColor SideToMove { get; private set; } = PieceColor.White;
        public bool IsBoardInitialized { get; private set; }
        public bool InputEnabled { get; private set; }
        public bool SoundEnabled { get; private set; } = true;
        public bool ReducedMotion { get; private set; }

        public ChessBoardGenerator BoardGenerator =>
            _boardGenerator != null ? _boardGenerator : (_boardGenerator = GetComponent<ChessBoardGenerator>());

        public PieceFactory PieceFactory =>
            _pieceFactory != null ? _pieceFactory : (_pieceFactory = GetComponent<PieceFactory>());

        public MobileMaterialPalette MaterialPalette =>
            _materialPalette ?? (_materialPalette = new MobileMaterialPalette());

        public IReadOnlyDictionary<SquareCoord, ChessPieceView> PiecesBySquare => _piecesBySquare;

        private void Awake()
        {
            EnsureComponents();
            if (buildOnAwake && !IsBoardInitialized)
            {
                InitializeDefaultPosition();
            }
        }

        private void OnDestroy()
        {
            if (_materialPalette != null)
            {
                _materialPalette.Dispose();
                _materialPalette = null;
            }
        }

        /// <summary>
        /// Generates the 8x8 board (<c>a1..h8</c>) and places the 32 initial pieces from the standard starting FEN.
        /// </summary>
        public void InitializeDefaultPosition()
        {
            EnsureComponents();
            BoardGenerator.GenerateBoard(MaterialPalette);
            IsBoardInitialized = true;

            string startingFen = string.IsNullOrWhiteSpace(initialFen)
                ? FenPlacementParser.StandardStartingFen
                : initialFen;

            if (!TryApplyFenSnapshot(startingFen, out string error))
            {
                Debug.LogError($"[BoardRenderer] Failed to apply initial FEN '{startingFen}': {error}");
            }
        }

        /// <summary>
        /// Validates and atomically reconstructs the 3D board pieces from a six-field FEN snapshot.
        /// If the FEN string is invalid, the existing board visual state is left untouched and false is returned.
        /// </summary>
        public bool TryApplyFenSnapshot(string fen, out string error)
        {
            EnsureComponents();

            if (!FenPlacementParser.TryParseFen(
                    fen,
                    out IReadOnlyList<PlacedPieceData> parsedPieces,
                    out PieceColor sideToMove,
                    out error))
            {
                return false;
            }

            if (!IsBoardInitialized || BoardGenerator.Squares.Count != SquareCoord.TotalSquares)
            {
                BoardGenerator.GenerateBoard(MaterialPalette);
                IsBoardInitialized = true;
            }

            BoardGenerator.ClearHighlights();
            RebuildPieceInstances(parsedPieces);

            CurrentFen = fen.Trim();
            SideToMove = sideToMove;
            return true;
        }

        /// <summary>
        /// Applies a JSON <c>board.snapshot</c> envelope or payload from the Flutter bridge.
        /// Validates the FEN before mutating any scene objects.
        /// </summary>
        public bool TryApplySnapshotJson(string json, out string error)
        {
            error = null;
            if (string.IsNullOrWhiteSpace(json))
            {
                error = "Snapshot JSON must not be empty.";
                return false;
            }

            BridgeSnapshotPayloadDto payload;
            try
            {
                if (json.Contains("\"payload\""))
                {
                    var envelope = JsonUtility.FromJson<BridgeEnvelopeDto>(json);
                    if (envelope == null || envelope.payload == null)
                    {
                        error = "Malformed bridge snapshot envelope.";
                        return false;
                    }

                    if (envelope.protocolVersion != 1)
                    {
                        error = $"Unsupported protocolVersion '{envelope.protocolVersion}'.";
                        return false;
                    }

                    payload = envelope.payload;
                }
                else
                {
                    payload = JsonUtility.FromJson<BridgeSnapshotPayloadDto>(json);
                }
            }
            catch (Exception ex)
            {
                error = $"Invalid JSON: {ex.Message}";
                return false;
            }

            if (payload == null || string.IsNullOrWhiteSpace(payload.fen))
            {
                error = "Snapshot payload is missing required 'fen' field.";
                return false;
            }

            if (!TryApplyFenSnapshot(payload.fen, out error))
            {
                return false;
            }

            InputEnabled = payload.inputEnabled;

            if (payload.camera != null && cameraController != null)
            {
                PieceColor orientation = string.Equals(
                    payload.camera.orientation,
                    "black",
                    StringComparison.OrdinalIgnoreCase)
                    ? PieceColor.Black
                    : PieceColor.White;
                cameraController.SetOrientation(orientation);
            }

            ApplyHighlightsFromSnapshot(payload.selectedSquare, payload.highlights);
            return true;
        }

        /// <summary>
        /// Applies sound, motion, and camera orientation preferences forwarded from the Flutter Settings controller.
        /// </summary>
        public void ConfigurePreferences(bool soundEnabled, bool reducedMotion, PieceColor cameraOrientation)
        {
            SoundEnabled = soundEnabled;
            ReducedMotion = reducedMotion;
            AudioListener.pause = !soundEnabled;
            if (cameraController != null)
            {
                cameraController.SetOrientation(cameraOrientation);
            }
        }

        /// <summary>
        /// Resets the 3D camera to the default bounded view for the current player perspective.
        /// </summary>
        public void ResetCamera()
        {
            if (cameraController != null)
            {
                cameraController.ResetCamera();
            }
        }

        public bool TryGetPieceAt(SquareCoord square, out ChessPieceView pieceView) =>
            _piecesBySquare.TryGetValue(square, out pieceView);

        public bool TryGetPieceAt(string algebraic, out ChessPieceView pieceView)
        {
            pieceView = null;
            return SquareCoord.TryParse(algebraic, out SquareCoord coord) &&
                   _piecesBySquare.TryGetValue(coord, out pieceView);
        }

        private void ApplyHighlightsFromSnapshot(string selectedSquare, BridgeHighlightsDto highlights)
        {
            BoardGenerator.ClearHighlights();

            string activeSelected = !string.IsNullOrEmpty(selectedSquare)
                ? selectedSquare
                : highlights?.selectedSquare;

            if (!string.IsNullOrEmpty(activeSelected) &&
                BoardGenerator.TryGetSquareView(activeSelected, out ChessSquareView selectedView))
            {
                selectedView.SetHighlightMaterial(MaterialPalette.SelectedSquareMaterial);
            }

            if (highlights?.moves == null)
            {
                return;
            }

            for (int i = 0; i < highlights.moves.Length; i++)
            {
                BridgeHighlightMoveDto move = highlights.moves[i];
                if (move != null &&
                    !string.IsNullOrEmpty(move.to) &&
                    BoardGenerator.TryGetSquareView(move.to, out ChessSquareView targetView))
                {
                    targetView.SetHighlightMaterial(MaterialPalette.LegalMoveSquareMaterial);
                }
            }
        }

        private void RebuildPieceInstances(IReadOnlyList<PlacedPieceData> pieces)
        {
            ClearPieces();

            var containerObject = new GameObject("BoardPieces");
            _piecesContainer = containerObject.transform;
            _piecesContainer.SetParent(transform, false);
            _piecesContainer.localPosition = Vector3.zero;
            _piecesContainer.localRotation = Quaternion.identity;

            for (int i = 0; i < pieces.Count; i++)
            {
                PlacedPieceData pieceData = pieces[i];
                Vector3 localPos = BoardGenerator.GetSquareSurfaceLocalPosition(pieceData.Square);
                ChessPieceView pieceView = PieceFactory.CreatePiece(
                    pieceData,
                    _piecesContainer,
                    localPos,
                    MaterialPalette);
                _piecesBySquare[pieceData.Square] = pieceView;
            }
        }

        public void ClearPieces()
        {
            _piecesBySquare.Clear();

            if (_piecesContainer != null)
            {
                DestroyObjectSafe(_piecesContainer.gameObject);
                _piecesContainer = null;
                return;
            }

            Transform existing = transform.Find("BoardPieces");
            if (existing != null)
            {
                DestroyObjectSafe(existing.gameObject);
            }
        }

        private void EnsureComponents()
        {
            if (_boardGenerator == null)
            {
                _boardGenerator = GetComponent<ChessBoardGenerator>();
                if (_boardGenerator == null)
                {
                    _boardGenerator = gameObject.AddComponent<ChessBoardGenerator>();
                }
            }

            if (_pieceFactory == null)
            {
                _pieceFactory = GetComponent<PieceFactory>();
                if (_pieceFactory == null)
                {
                    _pieceFactory = gameObject.AddComponent<PieceFactory>();
                }
            }

            if (cameraController == null && Camera.main != null)
            {
                cameraController = Camera.main.GetComponent<ChessCameraController>();
            }
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

