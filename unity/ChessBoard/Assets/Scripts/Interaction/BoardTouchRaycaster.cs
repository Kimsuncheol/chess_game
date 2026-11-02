using System;
using StillChess.Board.Board;
using StillChess.Board.Core;
using StillChess.Board.Rendering;
using UnityEngine;

namespace StillChess.Board.Interaction
{
    /// <summary>
    /// Mobile-optimized raycast input handler that translates screen taps into algebraic square intents (<c>a1..h8</c>).
    /// Does not validate legal moves or mutate piece positions; intents are forwarded to the host bridge.
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(BoardRenderer))]
    public sealed class BoardTouchRaycaster : MonoBehaviour
    {
        [SerializeField] private Camera raycastCamera;

        private BoardRenderer _boardRenderer;

        public event Action<SquareCoord> SquareTapped;

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
            if (_boardRenderer == null || !_boardRenderer.InputEnabled)
            {
                return;
            }

            if (Input.touchCount > 0)
            {
                Touch touch = Input.GetTouch(0);
                if (touch.phase == TouchPhase.Ended)
                {
                    TryPickSquareAtScreenPoint(touch.position);
                }
            }
            else if (Input.GetMouseButtonUp(0))
            {
                TryPickSquareAtScreenPoint(Input.mousePosition);
            }
        }

        public bool TryPickSquareAtScreenPoint(Vector2 screenPosition, out SquareCoord pickedSquare)
        {
            pickedSquare = default;
            Camera activeCamera = raycastCamera != null ? raycastCamera : Camera.main;
            if (activeCamera == null)
            {
                return false;
            }

            Ray ray = activeCamera.ScreenPointToRay(screenPosition);
            if (Physics.Raycast(ray, out RaycastHit hit, 100.0f))
            {
                ChessSquareView squareView = hit.collider.GetComponent<ChessSquareView>();
                if (squareView != null)
                {
                    pickedSquare = squareView.Coordinate;
                    SquareTapped?.Invoke(pickedSquare);
                    return true;
                }

                Vector3 localHit = transform.InverseTransformPoint(hit.point);
                if (SquareCoord.TryFromLocalPosition(localHit, _boardRenderer.BoardGenerator.SquareSize, out pickedSquare))
                {
                    SquareTapped?.Invoke(pickedSquare);
                    return true;
                }
            }

            return false;
        }

        private void TryPickSquareAtScreenPoint(Vector2 screenPosition)
        {
            TryPickSquareAtScreenPoint(screenPosition, out _);
        }
    }
}

