using System;
using StillChess.Board.Board;
using StillChess.Board.CameraControl;
using StillChess.Board.Core;
using StillChess.Board.Pieces;
using StillChess.Board.Rendering;
using UnityEngine;

namespace StillChess.Board.Interaction
{
    /// <summary>
    /// Mobile-optimized raycast and gesture input handler for the 3D chessboard.
    /// <list type="bullet">
    /// <item>Detects taps on both 3D chess pieces (<see cref="ChessPieceView"/>) and board squares (<see cref="ChessSquareView"/>).</item>
    /// <item>Resolves hit objects to canonical algebraic notation (<c>a1..h8</c>) and sends <c>player.squareSelected</c> to Flutter.</item>
    /// <item>Ignores board input whenever Flutter disables interaction (<see cref="BoardRenderer.InputEnabled"/> is false).</item>
    /// <item>Disambiguates taps from camera orbit drags and two-finger pinch-zoom gestures.</item>
    /// <item>Supports both Android touch input and Unity Editor mouse input.</item>
    /// </list>
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(BoardRenderer))]
    public sealed class BoardTouchRaycaster : MonoBehaviour
    {
        public const float DefaultMaxTapDisplacementPixels = 16.0f;
        public const float DefaultMaxTapDurationSeconds = 0.65f;

        [SerializeField] private Camera raycastCamera;
        [SerializeField] private float maxTapDisplacementPixels = DefaultMaxTapDisplacementPixels;
        [SerializeField] private float maxTapDurationSeconds = DefaultMaxTapDurationSeconds;

        private BoardRenderer _boardRenderer;
        private bool _pointerActive;
        private bool _dragExceededTapThreshold;
        private bool _multiTouchDetected;
        private Vector2 _pointerDownPosition;
        private Vector2 _lastPointerPosition;
        private float _pointerDownTime;
        private float _lastPinchDistance;

        public event Action<SquareCoord> SquareTapped;
        public event Action<SquareCoord, string> SquareSelectedJsonDispatched;

        public float MaxTapDisplacementPixels
        {
            get => maxTapDisplacementPixels;
            set => maxTapDisplacementPixels = Mathf.Max(1.0f, value);
        }

        public float MaxTapDurationSeconds
        {
            get => maxTapDurationSeconds;
            set => maxTapDurationSeconds = Mathf.Max(0.05f, value);
        }

        public Camera RaycastCamera
        {
            get => raycastCamera != null ? raycastCamera : (raycastCamera = Camera.main);
            set => raycastCamera = value;
        }

        public bool IsGestureActive => _pointerActive;
        public bool IsDraggingCamera => _pointerActive && _dragExceededTapThreshold;
        public bool IsMultiTouchGesture => _multiTouchDetected;

        private BoardRenderer Renderer =>
            _boardRenderer != null ? _boardRenderer : (_boardRenderer = GetComponent<BoardRenderer>());

        private void Awake()
        {
            _boardRenderer = GetComponent<BoardRenderer>();
            if (raycastCamera == null)
            {
                raycastCamera = Camera.main;
            }
        }

        private void Update()
        {
            if (Input.touchCount > 0)
            {
                ProcessAndroidTouchInput();
            }
            else
            {
                if (_multiTouchDetected)
                {
                    ResetGestureState();
                }

                ProcessEditorMouseInput();
            }
        }

        /// <summary>
        /// Starts tracking a single-finger touch or mouse-down gesture at the given screen position.
        /// </summary>
        public void BeginPointerGesture(Vector2 screenPosition, float timeSeconds, int activeTouchCount = 1)
        {
            if (activeTouchCount > 1)
            {
                _pointerActive = true;
                _multiTouchDetected = true;
                _dragExceededTapThreshold = true;
                return;
            }

            _pointerActive = true;
            _dragExceededTapThreshold = false;
            _multiTouchDetected = false;
            _pointerDownPosition = screenPosition;
            _lastPointerPosition = screenPosition;
            _pointerDownTime = timeSeconds;
        }

        /// <summary>
        /// Updates an active pointer gesture. If movement exceeds <see cref="MaxTapDisplacementPixels"/>
        /// or multiple touches are active, the gesture transitions to camera control and suppresses tap emission.
        /// </summary>
        public void UpdatePointerGesture(Vector2 currentScreenPosition, int activeTouchCount = 1)
        {
            if (!_pointerActive)
            {
                return;
            }

            if (activeTouchCount > 1)
            {
                _multiTouchDetected = true;
                _dragExceededTapThreshold = true;
                return;
            }

            Vector2 totalDelta = currentScreenPosition - _pointerDownPosition;
            Vector2 frameDelta = currentScreenPosition - _lastPointerPosition;
            _lastPointerPosition = currentScreenPosition;

            if (totalDelta.magnitude > maxTapDisplacementPixels)
            {
                _dragExceededTapThreshold = true;
            }

            if (_dragExceededTapThreshold && !_multiTouchDetected)
            {
                ChessCameraController cameraController = Renderer != null ? Renderer.CameraController : null;
                if (cameraController != null && frameDelta.sqrMagnitude > 0.0001f)
                {
                    cameraController.OrbitByScreenDelta(frameDelta);
                }
            }
        }

        /// <summary>
        /// Processes a two-finger pinch gesture on Android, routing the distance delta to the camera zoom
        /// and preventing any tap from firing when the fingers are lifted.
        /// </summary>
        public void UpdatePinchGesture(Vector2 firstTouchPos, Vector2 secondTouchPos, bool isPinchStart)
        {
            _pointerActive = true;
            _multiTouchDetected = true;
            _dragExceededTapThreshold = true;

            float currentDistance = Vector2.Distance(firstTouchPos, secondTouchPos);
            if (isPinchStart || _lastPinchDistance <= 0.001f)
            {
                _lastPinchDistance = currentDistance;
                return;
            }

            float delta = currentDistance - _lastPinchDistance;
            _lastPinchDistance = currentDistance;

            ChessCameraController cameraController = Renderer != null ? Renderer.CameraController : null;
            if (cameraController != null && Mathf.Abs(delta) > 0.01f)
            {
                cameraController.ZoomByPinchDelta(delta);
            }
        }

        /// <summary>
        /// Completes a pointer gesture. Emits a board square tap to Flutter only when:
        /// <list type="number">
        /// <item>The gesture was not a camera drag or pinch gesture.</item>
        /// <item>Flutter has enabled board input (<see cref="BoardRenderer.InputEnabled"/> is true).</item>
        /// <item>The raycast hits a valid chess piece or board square (<c>a1..h8</c>).</item>
        /// </list>
        /// </summary>
        public bool EndPointerGesture(
            Vector2 releaseScreenPosition,
            float timeSeconds,
            out SquareCoord tappedSquare,
            out string dispatchedJson)
        {
            tappedSquare = default;
            dispatchedJson = null;

            if (!_pointerActive)
            {
                return false;
            }

            float totalDisplacement = Vector2.Distance(_pointerDownPosition, releaseScreenPosition);
            float duration = Mathf.Max(0.0f, timeSeconds - _pointerDownTime);
            bool wasTap = !_multiTouchDetected &&
                          !_dragExceededTapThreshold &&
                          totalDisplacement <= maxTapDisplacementPixels &&
                          duration <= maxTapDurationSeconds;

            ResetGestureState();

            if (!wasTap)
            {
                return false;
            }

            if (Renderer == null || !Renderer.InputEnabled)
            {
                return false;
            }

            return TryPickSquareAtScreenPoint(releaseScreenPosition, out tappedSquare, out dispatchedJson);
        }

        public void CancelPointerGesture() => ResetGestureState();

        /// <summary>
        /// Raycasts from the active camera through <paramref name="screenPosition"/>, resolves either a hit
        /// <see cref="ChessPieceView"/> or <see cref="ChessSquareView"/> to its algebraic square (<c>a1..h8</c>),
        /// and dispatches <c>player.squareSelected</c> to Flutter when input is enabled.
        /// </summary>
        public bool TryPickSquareAtScreenPoint(Vector2 screenPosition, out SquareCoord pickedSquare) =>
            TryPickSquareAtScreenPoint(screenPosition, out pickedSquare, out _);

        public bool TryPickSquareAtScreenPoint(
            Vector2 screenPosition,
            out SquareCoord pickedSquare,
            out string dispatchedJson)
        {
            pickedSquare = default;
            dispatchedJson = null;

            if (Renderer == null || !Renderer.InputEnabled)
            {
                return false;
            }

            Camera activeCamera = RaycastCamera;
            if (activeCamera == null)
            {
                return false;
            }

            Ray ray = activeCamera.ScreenPointToRay(screenPosition);
            if (Physics.Raycast(ray, out RaycastHit hit, 100.0f))
            {
                if (TryResolveColliderToSquare(hit.collider, hit.point, out pickedSquare))
                {
                    return DispatchResolvedSquare(pickedSquare, out dispatchedJson);
                }
            }

            // Fallback analytical intersection with the board surface plane in case physics queries are disabled.
            Plane boardPlane = new Plane(transform.up, transform.position);
            if (boardPlane.Raycast(ray, out float enterDistance) && enterDistance > 0.0f)
            {
                Vector3 worldPoint = ray.GetPoint(enterDistance);
                Vector3 localPoint = transform.InverseTransformPoint(worldPoint);
                if (SquareCoord.TryFromLocalPosition(localPoint, Renderer.BoardGenerator.SquareSize, out pickedSquare))
                {
                    return DispatchResolvedSquare(pickedSquare, out dispatchedJson);
                }
            }

            return false;
        }

        /// <summary>
        /// Resolves a raycast-hit <see cref="Collider"/> (either a 3D piece collider or a board tile collider)
        /// into its corresponding <see cref="SquareCoord"/> (<c>a1..h8</c>), and dispatches the selection to Flutter
        /// if <paramref name="dispatchToBridge"/> is true and <see cref="BoardRenderer.InputEnabled"/> is true.
        /// </summary>
        public bool TrySelectObjectCollider(
            Collider hitCollider,
            Vector3 worldHitPoint,
            out SquareCoord square,
            out string dispatchedJson,
            bool dispatchToBridge = true)
        {
            square = default;
            dispatchedJson = null;

            if (Renderer == null || !Renderer.InputEnabled)
            {
                return false;
            }

            if (!TryResolveColliderToSquare(hitCollider, worldHitPoint, out square))
            {
                return false;
            }

            if (!dispatchToBridge)
            {
                return true;
            }

            return DispatchResolvedSquare(square, out dispatchedJson);
        }

        /// <summary>
        /// Pure resolution helper that converts a hit <see cref="ChessPieceView"/> collider,
        /// <see cref="ChessSquareView"/> collider, or board world position into a <see cref="SquareCoord"/>.
        /// </summary>
        public bool TryResolveColliderToSquare(
            Collider hitCollider,
            Vector3 worldHitPoint,
            out SquareCoord square)
        {
            square = default;
            if (hitCollider != null)
            {
                ChessPieceView pieceView = hitCollider.GetComponentInParent<ChessPieceView>();
                if (pieceView != null)
                {
                    square = pieceView.Square;
                    return true;
                }

                ChessSquareView squareView = hitCollider.GetComponentInParent<ChessSquareView>();
                if (squareView != null)
                {
                    square = squareView.Coordinate;
                    return true;
                }
            }

            if (Renderer != null)
            {
                Vector3 localHit = transform.InverseTransformPoint(worldHitPoint);
                return SquareCoord.TryFromLocalPosition(localHit, Renderer.BoardGenerator.SquareSize, out square);
            }

            return false;
        }

        private bool DispatchResolvedSquare(SquareCoord pickedSquare, out string dispatchedJson)
        {
            dispatchedJson = null;
            if (Renderer == null || !Renderer.ReportSquareSelected(pickedSquare, out dispatchedJson, "tap"))
            {
                return false;
            }

            SquareTapped?.Invoke(pickedSquare);
            SquareSelectedJsonDispatched?.Invoke(pickedSquare, dispatchedJson);
            return true;
        }

        private void ProcessAndroidTouchInput()
        {
            if (Input.touchCount >= 2)
            {
                Touch touch0 = Input.GetTouch(0);
                Touch touch1 = Input.GetTouch(1);
                bool isPinchStart = touch0.phase == TouchPhase.Began || touch1.phase == TouchPhase.Began;
                UpdatePinchGesture(touch0.position, touch1.position, isPinchStart);
                return;
            }

            Touch touch = Input.GetTouch(0);
            switch (touch.phase)
            {
                case TouchPhase.Began:
                    if (!_multiTouchDetected)
                    {
                        BeginPointerGesture(touch.position, Time.unscaledTime, activeTouchCount: 1);
                    }
                    break;

                case TouchPhase.Moved:
                case TouchPhase.Stationary:
                    UpdatePointerGesture(touch.position, activeTouchCount: 1);
                    break;

                case TouchPhase.Ended:
                    EndPointerGesture(touch.position, Time.unscaledTime, out _, out _);
                    break;

                case TouchPhase.Canceled:
                    CancelPointerGesture();
                    break;
            }
        }

        private void ProcessEditorMouseInput()
        {
            if (Input.GetMouseButtonDown(0))
            {
                BeginPointerGesture(Input.mousePosition, Time.unscaledTime, activeTouchCount: 1);
            }
            else if (Input.GetMouseButton(0))
            {
                UpdatePointerGesture(Input.mousePosition, activeTouchCount: 1);
            }
            else if (Input.GetMouseButtonUp(0))
            {
                EndPointerGesture(Input.mousePosition, Time.unscaledTime, out _, out _);
            }

            float scrollDelta = Input.mouseScrollDelta.y;
            if (Mathf.Abs(scrollDelta) > 0.001f && Renderer != null && Renderer.CameraController != null)
            {
                Renderer.CameraController.ZoomByPinchDelta(scrollDelta * 25.0f);
            }
        }

        private void ResetGestureState()
        {
            _pointerActive = false;
            _dragExceededTapThreshold = false;
            _multiTouchDetected = false;
            _lastPinchDistance = 0.0f;
        }
    }
}
