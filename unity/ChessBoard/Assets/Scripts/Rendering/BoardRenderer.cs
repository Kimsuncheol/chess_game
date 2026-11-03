using System;
using System.Collections.Generic;
using StillChess.Board.Board;
using StillChess.Board.Bridge;
using StillChess.Board.CameraControl;
using StillChess.Board.Core;
using StillChess.Board.Materials;
using StillChess.Board.Pieces;
using UnityEngine;

namespace StillChess.Board.Rendering
{
    /// <summary>
    /// Presentation-only 3D chessboard renderer that reconstructs the 8x8 board and piece layout
    /// from authoritative six-field FEN snapshots sent by Flutter, renders selected-square and
    /// legal-move highlights, and emits <c>player.squareSelected</c> intents over the JSON bridge.
    /// <para>
    /// By architectural contract (<c>docs/unity_flutter_bridge.md</c>), Unity never computes legal moves,
    /// validates turns, or adjudicates game results.
    /// </para>
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(ChessBoardGenerator))]
    [RequireComponent(typeof(PieceFactory))]
    public sealed class BoardRenderer : MonoBehaviour
    {
        [SerializeField] private string initialFen = FenPlacementParser.StandardStartingFen;
        [SerializeField] private bool buildOnAwake = true;
        [SerializeField] private ChessCameraController cameraController;

        private readonly Dictionary<SquareCoord, ChessPieceView> _piecesBySquare =
            new Dictionary<SquareCoord, ChessPieceView>(32);

        private readonly Dictionary<SquareCoord, SquareHighlightState> _highlightedMoves =
            new Dictionary<SquareCoord, SquareHighlightState>(16);

        private readonly DefaultFlutterBridgeTransport _defaultTransport =
            new DefaultFlutterBridgeTransport();

        private ChessBoardGenerator _boardGenerator;
        private PieceFactory _pieceFactory;
        private MobileMaterialPalette _materialPalette;
        private IFlutterBridgeTransport _bridgeTransport;
        private Transform _piecesContainer;
        private int _outgoingSequence;

        public event Action<string> OutgoingBridgeMessageSent;

        public string CurrentFen { get; private set; } = string.Empty;
        public PieceColor SideToMove { get; private set; } = PieceColor.White;
        public bool IsBoardInitialized { get; private set; }
        public bool InputEnabled { get; private set; }
        public bool SoundEnabled { get; private set; } = true;
        public bool ReducedMotion { get; private set; }

        public string SessionId { get; private set; } = "session-local";
        public string GameId { get; private set; } = "game-local";
        public int CurrentRevision { get; private set; }
        public string ActiveSelectionRequestId { get; private set; }
        public SquareCoord? SelectedSquare { get; private set; }

        public IReadOnlyDictionary<SquareCoord, SquareHighlightState> HighlightedMoves => _highlightedMoves;

        public IFlutterBridgeTransport BridgeTransport
        {
            get => _bridgeTransport ?? _defaultTransport;
            set => _bridgeTransport = value;
        }

        public DefaultFlutterBridgeTransport DefaultTransport => _defaultTransport;

        public ChessBoardGenerator BoardGenerator =>
            _boardGenerator != null ? _boardGenerator : (_boardGenerator = GetComponent<ChessBoardGenerator>());

        public PieceFactory PieceFactory =>
            _pieceFactory != null ? _pieceFactory : (_pieceFactory = GetComponent<PieceFactory>());

        public ChessCameraController CameraController
        {
            get
            {
                if (cameraController == null && Camera.main != null)
                {
                    cameraController = Camera.main.GetComponent<ChessCameraController>();
                }

                return cameraController;
            }
            set => cameraController = value;
        }

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
        /// Explicitly enables or disables board touch interaction from Flutter.
        /// </summary>
        public void SetInputEnabled(bool enabled)
        {
            InputEnabled = enabled;
        }

        /// <summary>
        /// Binds session, game, and revision metadata for bridge correlation.
        /// </summary>
        public void BindSessionContext(string sessionId, string gameId, int revision, bool inputEnabled = true)
        {
            if (!string.IsNullOrEmpty(sessionId))
            {
                SessionId = sessionId;
            }

            if (!string.IsNullOrEmpty(gameId))
            {
                GameId = gameId;
            }

            CurrentRevision = Mathf.Max(0, revision);
            InputEnabled = inputEnabled;
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

            ClearHighlights();
            RebuildPieceInstances(parsedPieces);

            CurrentFen = fen.Trim();
            SideToMove = sideToMove;
            return true;
        }

        /// <summary>
        /// Unity <c>SendMessage</c>-compatible entry point for receiving JSON bridge commands from Flutter.
        /// </summary>
        public void OnFlutterBridgeMessage(string json)
        {
            if (!ReceiveBridgeMessage(json, out string error))
            {
                Debug.LogWarning($"[BoardRenderer] Rejected bridge message: {error}");
            }
        }

        /// <summary>
        /// Processes incoming JSON bridge messages from Flutter (<c>board.snapshot</c>,
        /// <c>legalMoves.highlight</c>, <c>game.status</c>, <c>camera.reset</c>).
        /// </summary>
        public bool ReceiveBridgeMessage(string json, out string error)
        {
            error = null;
            if (string.IsNullOrWhiteSpace(json))
            {
                error = "Bridge message JSON must not be empty.";
                return false;
            }

            if (!json.Contains("\"type\"") || !json.Contains("\"payload\""))
            {
                return TryApplySnapshotJson(json, out error);
            }

            BridgeIncomingEnvelopeDto envelope;
            try
            {
                envelope = JsonUtility.FromJson<BridgeIncomingEnvelopeDto>(json);
            }
            catch (Exception ex)
            {
                error = $"Invalid bridge JSON: {ex.Message}";
                return false;
            }

            if (envelope == null || envelope.payload == null)
            {
                error = "Bridge envelope or payload is missing.";
                return false;
            }

            if (envelope.protocolVersion != BridgeProtocolMessages.SupportedProtocolVersion)
            {
                InputEnabled = false;
                error = $"Unsupported protocolVersion '{envelope.protocolVersion}'.";
                return false;
            }

            switch (envelope.type)
            {
                case BridgeProtocolMessages.TypeBoardSnapshot:
                    return ApplySnapshotEnvelope(envelope, out error);

                case BridgeProtocolMessages.TypeLegalMovesHighlight:
                    return ApplyHighlightEnvelope(envelope, out error);

                case BridgeProtocolMessages.TypeGameStatus:
                    return ApplyStatusEnvelope(envelope, out error);

                case BridgeProtocolMessages.TypeCameraReset:
                    return ApplyCameraResetEnvelope(envelope, out error);

                default:
                    error = $"Unsupported message type '{envelope.type}'.";
                    return false;
            }
        }

        /// <summary>
        /// Applies a JSON <c>board.snapshot</c> envelope or standalone snapshot payload from the Flutter bridge.
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

            try
            {
                if (json.Contains("\"payload\""))
                {
                    var envelope = JsonUtility.FromJson<BridgeIncomingEnvelopeDto>(json);
                    if (envelope == null || envelope.payload == null)
                    {
                        error = "Malformed bridge snapshot envelope.";
                        return false;
                    }

                    if (envelope.protocolVersion != BridgeProtocolMessages.SupportedProtocolVersion)
                    {
                        InputEnabled = false;
                        error = $"Unsupported protocolVersion '{envelope.protocolVersion}'.";
                        return false;
                    }

                    return ApplySnapshotEnvelope(envelope, out error);
                }

                var payload = JsonUtility.FromJson<BridgeIncomingPayloadDto>(json);
                if (payload == null)
                {
                    error = "Malformed snapshot payload.";
                    return false;
                }

                return ApplySnapshotPayload(payload, out error);
            }
            catch (Exception ex)
            {
                error = $"Invalid JSON: {ex.Message}";
                return false;
            }
        }

        /// <summary>
        /// Applies selected-square and legal-move highlights supplied by Flutter.
        /// Unity uses this strictly for visual feedback and correlation (<c>selectionRequestId</c>);
        /// it never uses highlights to decide move legality locally.
        /// </summary>
        public void ApplyLegalMovesHighlight(
            string selectionRequestId,
            string selectedSquare,
            IReadOnlyList<BridgeHighlightMoveDto> moves,
            bool inputEnabled)
        {
            EnsureComponents();
            ClearHighlights();

            InputEnabled = inputEnabled;

            if (!string.IsNullOrEmpty(selectedSquare) &&
                SquareCoord.TryParse(selectedSquare, out SquareCoord selectedCoord) &&
                BoardGenerator.TryGetSquareView(selectedCoord, out ChessSquareView selectedView))
            {
                SelectedSquare = selectedCoord;
                ActiveSelectionRequestId = string.IsNullOrEmpty(selectionRequestId) ? null : selectionRequestId;
                selectedView.ApplyHighlight(SquareHighlightState.Selected, MaterialPalette.SelectedSquareMaterial);
            }

            if (moves == null || moves.Count == 0)
            {
                if (SelectedSquare == null)
                {
                    ActiveSelectionRequestId = null;
                }

                return;
            }

            for (int i = 0; i < moves.Count; i++)
            {
                BridgeHighlightMoveDto move = moves[i];
                if (move == null || string.IsNullOrEmpty(move.to))
                {
                    continue;
                }

                if (!SquareCoord.TryParse(move.to, out SquareCoord targetCoord) ||
                    !BoardGenerator.TryGetSquareView(targetCoord, out ChessSquareView targetView))
                {
                    continue;
                }

                bool isCapture = string.Equals(move.style, "capture", StringComparison.OrdinalIgnoreCase);
                SquareHighlightState state = isCapture
                    ? SquareHighlightState.LegalCapture
                    : SquareHighlightState.LegalQuiet;
                Material material = isCapture
                    ? MaterialPalette.LegalCaptureSquareMaterial
                    : MaterialPalette.LegalMoveSquareMaterial;

                _highlightedMoves[targetCoord] = state;
                targetView.ApplyHighlight(state, material);
            }
        }

        public void ClearHighlights()
        {
            SelectedSquare = null;
            ActiveSelectionRequestId = null;
            _highlightedMoves.Clear();
            if (_boardGenerator != null)
            {
                _boardGenerator.ClearHighlights();
            }
        }

        /// <summary>
        /// Emits a <c>player.squareSelected</c> message to Flutter for the given algebraic square.
        /// Ignores the interaction when <see cref="InputEnabled"/> is false, and never decides move legality in Unity.
        /// </summary>
        public bool ReportSquareSelected(SquareCoord square, string interaction = "tap") =>
            ReportSquareSelected(square, out _, interaction);

        /// <summary>
        /// Emits a <c>player.squareSelected</c> message to Flutter and outputs the serialized JSON message.
        /// </summary>
        public bool ReportSquareSelected(SquareCoord square, out string sentJson, string interaction = "tap")
        {
            sentJson = null;
            if (!InputEnabled || !IsBoardInitialized)
            {
                return false;
            }

            int sequence = ++_outgoingSequence;
            string messageId = $"u-select-{sequence}";
            sentJson = BridgeProtocolMessages.BuildSquareSelectedJson(
                messageId: messageId,
                sessionId: SessionId,
                gameId: GameId,
                revision: CurrentRevision,
                sequence: sequence,
                square: square.Algebraic,
                interaction: string.IsNullOrEmpty(interaction) ? "tap" : interaction,
                selectionRequestId: ActiveSelectionRequestId,
                replyTo: null);

            BridgeTransport.SendToFlutter(sentJson);
            OutgoingBridgeMessageSent?.Invoke(sentJson);
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
            if (CameraController != null)
            {
                CameraController.SetOrientation(cameraOrientation);
            }
        }

        /// <summary>
        /// Resets the 3D camera to the default bounded view for the current player perspective.
        /// </summary>
        public void ResetCamera()
        {
            if (CameraController != null)
            {
                CameraController.ResetCamera();
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

        private bool ApplySnapshotEnvelope(BridgeIncomingEnvelopeDto envelope, out string error)
        {
            if (!ApplySnapshotPayload(envelope.payload, out error))
            {
                return false;
            }

            if (!string.IsNullOrEmpty(envelope.sessionId))
            {
                SessionId = envelope.sessionId;
            }

            if (!string.IsNullOrEmpty(envelope.gameId))
            {
                GameId = envelope.gameId;
            }

            CurrentRevision = Mathf.Max(0, envelope.revision);
            return true;
        }

        private bool ApplySnapshotPayload(BridgeIncomingPayloadDto payload, out string error)
        {
            if (payload == null || string.IsNullOrWhiteSpace(payload.fen))
            {
                error = "Snapshot payload is missing required 'fen' field.";
                return false;
            }

            if (!TryApplyFenSnapshot(payload.fen, out error))
            {
                return false;
            }

            bool allowInput = payload.inputEnabled &&
                              (payload.status == null ||
                               string.IsNullOrEmpty(payload.status.phase) ||
                               string.Equals(payload.status.phase, "humanTurn", StringComparison.Ordinal));

            if (payload.camera != null && CameraController != null)
            {
                PieceColor orientation = string.Equals(
                    payload.camera.orientation,
                    "black",
                    StringComparison.OrdinalIgnoreCase)
                    ? PieceColor.Black
                    : PieceColor.White;
                CameraController.SetOrientation(orientation);
            }

            string selectedSquare = !string.IsNullOrEmpty(payload.selectedSquare)
                ? payload.selectedSquare
                : payload.highlights?.selectedSquare;
            string selectionRequestId = payload.highlights?.selectionRequestId;
            BridgeHighlightMoveDto[] moves = payload.highlights?.moves;

            ApplyLegalMovesHighlight(selectionRequestId, selectedSquare, moves, allowInput);
            return true;
        }

        private bool ApplyHighlightEnvelope(BridgeIncomingEnvelopeDto envelope, out string error)
        {
            error = null;
            if (!IsBoardInitialized)
            {
                error = "Board is not initialized.";
                return false;
            }

            if (envelope.revision != CurrentRevision)
            {
                error = $"Highlight revision {envelope.revision} does not match current revision {CurrentRevision}.";
                return false;
            }

            string requestId = !string.IsNullOrEmpty(envelope.messageId)
                ? envelope.messageId
                : envelope.payload.highlights?.selectionRequestId;
            string selectedSquare = !string.IsNullOrEmpty(envelope.payload.selectedSquare)
                ? envelope.payload.selectedSquare
                : envelope.payload.highlights?.selectedSquare;
            BridgeHighlightMoveDto[] moves = envelope.payload.moves ?? envelope.payload.highlights?.moves;

            ApplyLegalMovesHighlight(
                selectionRequestId: requestId,
                selectedSquare: selectedSquare,
                moves: moves,
                inputEnabled: envelope.payload.inputEnabled);
            return true;
        }

        private bool ApplyStatusEnvelope(BridgeIncomingEnvelopeDto envelope, out string error)
        {
            error = null;
            if (envelope.revision != CurrentRevision)
            {
                error = $"Status revision {envelope.revision} does not match current revision {CurrentRevision}.";
                return false;
            }

            bool phaseAllowsInput = envelope.payload.status == null ||
                                    string.IsNullOrEmpty(envelope.payload.status.phase) ||
                                    string.Equals(envelope.payload.status.phase, "humanTurn", StringComparison.Ordinal);
            InputEnabled = envelope.payload.inputEnabled && phaseAllowsInput;
            if (!InputEnabled)
            {
                ClearHighlights();
            }

            return true;
        }

        private bool ApplyCameraResetEnvelope(BridgeIncomingEnvelopeDto envelope, out string error)
        {
            error = null;
            if (CameraController != null)
            {
                if (!string.IsNullOrEmpty(envelope.payload.orientation))
                {
                    PieceColor orientation = string.Equals(
                        envelope.payload.orientation,
                        "black",
                        StringComparison.OrdinalIgnoreCase)
                        ? PieceColor.Black
                        : PieceColor.White;
                    CameraController.SetOrientation(orientation);
                }

                CameraController.ResetCamera();
            }

            return true;
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
