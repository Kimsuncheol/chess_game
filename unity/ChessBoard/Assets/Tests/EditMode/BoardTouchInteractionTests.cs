using NUnit.Framework;
using StillChess.Board.Board;
using StillChess.Board.CameraControl;
using StillChess.Board.Core;
using StillChess.Board.Interaction;
using StillChess.Board.Pieces;
using StillChess.Board.Rendering;
using UnityEngine;

namespace StillChess.Board.Tests
{
    public sealed class BoardTouchInteractionTests
    {
        private GameObject _cameraObject;
        private Camera _camera;
        private ChessCameraController _cameraController;
        private GameObject _rootObject;
        private BoardRenderer _boardRenderer;
        private BoardTouchRaycaster _touchRaycaster;

        [SetUp]
        public void SetUp()
        {
            _cameraObject = new GameObject("TestMainCamera");
            _cameraObject.tag = "MainCamera";
            _camera = _cameraObject.AddComponent<Camera>();
            _camera.pixelRect = new Rect(0, 0, 1080, 1920);
            _cameraController = _cameraObject.AddComponent<ChessCameraController>();
            _cameraController.ResetCamera();

            _rootObject = new GameObject("TestChessBoardRoot");
            _boardRenderer = _rootObject.AddComponent<BoardRenderer>();
            _boardRenderer.CameraController = _cameraController;
            _touchRaycaster = _rootObject.AddComponent<BoardTouchRaycaster>();
            _touchRaycaster.RaycastCamera = _camera;

            _boardRenderer.InitializeDefaultPosition();
            _boardRenderer.BindSessionContext("session-A", "game-1", revision: 0, inputEnabled: true);
            Physics.SyncTransforms();
        }

        [TearDown]
        public void TearDown()
        {
            if (_rootObject != null)
            {
                Object.DestroyImmediate(_rootObject);
            }

            if (_cameraObject != null)
            {
                Object.DestroyImmediate(_cameraObject);
            }
        }

        [Test]
        public void TapOnPieceAndSquare_ConvertsObjectToAlgebraicSquareAndSendsAgreedJsonProtocol()
        {
            // 1. Tap on the White Pawn piece on e2.
            Assert.That(_boardRenderer.TryGetPieceAt("e2", out ChessPieceView e2Pawn), Is.True);
            var pawnCollider = e2Pawn.GetComponent<Collider>();
            Assert.That(pawnCollider, Is.Not.Null, "Every 3D piece must have a root collider for tap detection.");

            bool pieceSelected = _touchRaycaster.TrySelectObjectCollider(
                pawnCollider,
                e2Pawn.transform.position,
                out SquareCoord selectedPieceSquare,
                out string pieceJson);

            Assert.That(pieceSelected, Is.True);
            Assert.That(selectedPieceSquare.Algebraic, Is.EqualTo("e2"));
            Assert.That(pieceJson, Does.Contain("\"protocolVersion\":1"));
            Assert.That(pieceJson, Does.Contain("\"type\":\"player.squareSelected\""));
            Assert.That(pieceJson, Does.Contain("\"sessionId\":\"session-A\""));
            Assert.That(pieceJson, Does.Contain("\"gameId\":\"game-1\""));
            Assert.That(pieceJson, Does.Contain("\"revision\":0"));
            Assert.That(pieceJson, Does.Contain("\"square\":\"e2\""));
            Assert.That(pieceJson, Does.Contain("\"interaction\":\"tap\""));
            Assert.That(pieceJson, Does.Contain("\"selectionRequestId\":null"));

            // 2. Tap on the empty board square e4.
            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("e4", out ChessSquareView e4SquareView), Is.True);
            var squareCollider = e4SquareView.GetComponent<Collider>();

            bool squareSelected = _touchRaycaster.TrySelectObjectCollider(
                squareCollider,
                e4SquareView.transform.position,
                out SquareCoord selectedTileSquare,
                out string squareJson);

            Assert.That(squareSelected, Is.True);
            Assert.That(selectedTileSquare.Algebraic, Is.EqualTo("e4"));
            Assert.That(squareJson, Does.Contain("\"square\":\"e4\""));
            Assert.That(_boardRenderer.DefaultTransport.SentMessages.Count, Is.EqualTo(2));

            // Requirement 5: Unity never decides move legality or moves pieces locally on tap.
            Assert.That(_boardRenderer.TryGetPieceAt("e2", out _), Is.True);
            Assert.That(_boardRenderer.TryGetPieceAt("e4", out _), Is.False);
        }

        [Test]
        public void ReceiveLegalMovesHighlight_DisplaysSelectedAndLegalMoveHighlightsAndCorrelatesSelectionRequestId()
        {
            const string highlightJson = @"{
              ""protocolVersion"": 1,
              ""type"": ""legalMoves.highlight"",
              ""messageId"": ""f-highlight-1"",
              ""sessionId"": ""session-A"",
              ""gameId"": ""game-1"",
              ""revision"": 0,
              ""sequence"": 2,
              ""replyTo"": ""u-select-1"",
              ""payload"": {
                ""selectedSquare"": ""e2"",
                ""moves"": [
                  {""to"": ""e3"", ""style"": ""quiet"", ""promotionChoices"": []},
                  {""to"": ""e4"", ""style"": ""quiet"", ""promotionChoices"": []},
                  {""to"": ""d3"", ""style"": ""capture"", ""promotionChoices"": []}
                ],
                ""inputEnabled"": true
              }
            }";

            bool ok = _boardRenderer.ReceiveBridgeMessage(highlightJson, out string error);
            Assert.That(ok, Is.True, error);
            Assert.That(_boardRenderer.SelectedSquare?.Algebraic, Is.EqualTo("e2"));
            Assert.That(_boardRenderer.ActiveSelectionRequestId, Is.EqualTo("f-highlight-1"));

            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("e2", out ChessSquareView e2View), Is.True);
            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("e3", out ChessSquareView e3View), Is.True);
            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("e4", out ChessSquareView e4View), Is.True);
            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("d3", out ChessSquareView d3View), Is.True);
            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("a1", out ChessSquareView a1View), Is.True);

            Assert.That(e2View.HighlightState, Is.EqualTo(SquareHighlightState.Selected));
            Assert.That(e3View.HighlightState, Is.EqualTo(SquareHighlightState.LegalQuiet));
            Assert.That(e4View.HighlightState, Is.EqualTo(SquareHighlightState.LegalQuiet));
            Assert.That(d3View.HighlightState, Is.EqualTo(SquareHighlightState.LegalCapture));
            Assert.That(a1View.HighlightState, Is.EqualTo(SquareHighlightState.None));

            // Subsequent destination tap includes selectionRequestId: "f-highlight-1".
            bool tappedDestination = _touchRaycaster.TrySelectObjectCollider(
                e4View.GetComponent<Collider>(),
                e4View.transform.position,
                out SquareCoord destCoord,
                out string destJson);

            Assert.That(tappedDestination, Is.True);
            Assert.That(destCoord.Algebraic, Is.EqualTo("e4"));
            Assert.That(destJson, Does.Contain("\"square\":\"e4\""));
            Assert.That(destJson, Does.Contain("\"selectionRequestId\":\"f-highlight-1\""));
        }

        [Test]
        public void DisabledInput_IgnoresBoardTapsWhenFlutterDisablesInteraction()
        {
            const string statusJson = @"{
              ""protocolVersion"": 1,
              ""type"": ""game.status"",
              ""messageId"": ""f-status-1"",
              ""sessionId"": ""session-A"",
              ""gameId"": ""game-1"",
              ""revision"": 0,
              ""sequence"": 3,
              ""replyTo"": null,
              ""payload"": {
                ""status"": {
                  ""phase"": ""aiThinking"",
                  ""sideToMove"": ""black"",
                  ""checkSquare"": null,
                  ""result"": ""*"",
                  ""termination"": null,
                  ""canClaimDraw"": false
                },
                ""inputEnabled"": false
              }
            }";

            Assert.That(_boardRenderer.ReceiveBridgeMessage(statusJson, out string error), Is.True, error);
            Assert.That(_boardRenderer.InputEnabled, Is.False);

            Assert.That(_boardRenderer.TryGetPieceAt("e2", out ChessPieceView e2Pawn), Is.True);
            bool selected = _touchRaycaster.TrySelectObjectCollider(
                e2Pawn.GetComponent<Collider>(),
                e2Pawn.transform.position,
                out _,
                out string json);

            Assert.That(selected, Is.False);
            Assert.That(json, Is.Null);
            Assert.That(_boardRenderer.DefaultTransport.SentMessages, Is.Empty);
        }

        [Test]
        public void GestureDisambiguation_AvoidsTreatingCameraDragOrPinchAsTap()
        {
            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("e2", out ChessSquareView e2View), Is.True);
            Vector3 e2ScreenPos3D = _camera.WorldToScreenPoint(e2View.transform.position);
            Vector2 e2ScreenPos = new Vector2(e2ScreenPos3D.x, e2ScreenPos3D.y);

            // 1. Camera drag gesture: pointer moves 45 pixels (exceeds 16px tap slop) and releases over e2.
            float initialYaw = _cameraController.CurrentYawDegrees;
            _touchRaycaster.BeginPointerGesture(e2ScreenPos - new Vector2(45.0f, 0.0f), timeSeconds: 1.0f);
            _touchRaycaster.UpdatePointerGesture(e2ScreenPos, activeTouchCount: 1);
            bool dragTriggeredTap = _touchRaycaster.EndPointerGesture(
                e2ScreenPos,
                timeSeconds: 1.15f,
                out _,
                out string dragJson);

            Assert.That(dragTriggeredTap, Is.False, "Camera drag must not be treated as a board tap.");
            Assert.That(dragJson, Is.Null);
            Assert.That(_cameraController.CurrentYawDegrees, Is.Not.EqualTo(initialYaw));

            // 2. Two-finger pinch gesture: must zoom camera and never emit a tap on release.
            float initialDistance = _cameraController.CurrentDistance;
            _touchRaycaster.UpdatePinchGesture(
                e2ScreenPos - new Vector2(50.0f, 0.0f),
                e2ScreenPos + new Vector2(50.0f, 0.0f),
                isPinchStart: true);
            _touchRaycaster.UpdatePinchGesture(
                e2ScreenPos - new Vector2(90.0f, 0.0f),
                e2ScreenPos + new Vector2(90.0f, 0.0f),
                isPinchStart: false);
            bool pinchTriggeredTap = _touchRaycaster.EndPointerGesture(
                e2ScreenPos,
                timeSeconds: 2.1f,
                out _,
                out string pinchJson);

            Assert.That(pinchTriggeredTap, Is.False, "Pinch zoom must not be treated as a board tap.");
            Assert.That(pinchJson, Is.Null);
            Assert.That(_cameraController.CurrentDistance, Is.LessThan(initialDistance));

            // 3. Clean stationary tap within threshold (< 16px, < 0.65s) succeeds and emits player.squareSelected.
            _cameraController.ResetCamera();
            Physics.SyncTransforms();
            Vector3 cleanScreenPos3D = _camera.WorldToScreenPoint(e2View.transform.position);
            Vector2 cleanScreenPos = new Vector2(cleanScreenPos3D.x, cleanScreenPos3D.y);

            _touchRaycaster.BeginPointerGesture(cleanScreenPos, timeSeconds: 3.0f);
            _touchRaycaster.UpdatePointerGesture(cleanScreenPos + new Vector2(3.0f, 2.0f), activeTouchCount: 1);
            bool tapSucceeded = _touchRaycaster.EndPointerGesture(
                cleanScreenPos + new Vector2(3.0f, 2.0f),
                timeSeconds: 3.12f,
                out SquareCoord tappedSquare,
                out string tapJson);

            Assert.That(tapSucceeded, Is.True);
            Assert.That(tappedSquare.Algebraic, Is.EqualTo("e2"));
            Assert.That(tapJson, Does.Contain("\"square\":\"e2\""));
        }
    }
}

