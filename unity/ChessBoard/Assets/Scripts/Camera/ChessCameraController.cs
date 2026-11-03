using StillChess.Board.Core;
using UnityEngine;

namespace StillChess.Board.CameraControl
{
    /// <summary>
    /// Mobile-friendly perspective camera controller for the 3D chessboard.
    /// Supports White and Black player perspectives, bounded orbit/zoom gestures, and camera reset.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class ChessCameraController : MonoBehaviour
    {
        public const float MinPitchDegrees = 22.0f;
        public const float MaxPitchDegrees = 82.0f;
        public const float MinDistance = 6.5f;
        public const float MaxDistance = 15.5f;

        [SerializeField] private Vector3 boardTarget = new Vector3(0.0f, 0.1f, 0.0f);
        [SerializeField] private float defaultDistance = 10.2f;
        [SerializeField] private float defaultPitchDegrees = 52.0f;
        [SerializeField] private float orbitDegreesPerPixel = 0.22f;
        [SerializeField] private float pinchZoomUnitsPerPixel = 0.015f;
        [SerializeField] private PieceColor currentOrientation = PieceColor.White;

        private float _currentYawOffsetDegrees;
        private float _currentPitchDegrees = 52.0f;
        private float _currentDistance = 10.2f;

        public PieceColor CurrentOrientation => currentOrientation;
        public float CurrentYawDegrees => GetBaseYawDegrees(currentOrientation) + _currentYawOffsetDegrees;
        public float CurrentPitchDegrees => _currentPitchDegrees;
        public float CurrentDistance => _currentDistance;

        private void Awake()
        {
            ResetCamera();
        }

        public void SetOrientation(PieceColor orientation)
        {
            currentOrientation = orientation;
            ApplyCameraTransform();
        }

        public void OrbitByScreenDelta(Vector2 screenDeltaPixels)
        {
            _currentYawOffsetDegrees = Mathf.Repeat(
                _currentYawOffsetDegrees + (screenDeltaPixels.x * orbitDegreesPerPixel) + 180.0f,
                360.0f) - 180.0f;
            _currentPitchDegrees = Mathf.Clamp(
                _currentPitchDegrees - (screenDeltaPixels.y * orbitDegreesPerPixel),
                MinPitchDegrees,
                MaxPitchDegrees);
            ApplyCameraTransform();
        }

        public void ZoomByPinchDelta(float pinchDistanceDeltaPixels)
        {
            _currentDistance = Mathf.Clamp(
                _currentDistance - (pinchDistanceDeltaPixels * pinchZoomUnitsPerPixel),
                MinDistance,
                MaxDistance);
            ApplyCameraTransform();
        }

        public void ResetCamera()
        {
            _currentYawOffsetDegrees = 0.0f;
            _currentPitchDegrees = defaultPitchDegrees;
            _currentDistance = defaultDistance;
            ApplyCameraTransform();
        }

        public void ApplyCameraTransform()
        {
            float yawDegrees = CurrentYawDegrees;
            float pitchRad = _currentPitchDegrees * Mathf.Deg2Rad;
            float yawRad = yawDegrees * Mathf.Deg2Rad;

            float horizontalRadius = Mathf.Cos(pitchRad) * _currentDistance;
            float height = Mathf.Sin(pitchRad) * _currentDistance;

            var offset = new Vector3(
                -Mathf.Sin(yawRad) * horizontalRadius,
                height,
                -Mathf.Cos(yawRad) * horizontalRadius);

            transform.position = boardTarget + offset;
            transform.LookAt(boardTarget, Vector3.up);
        }

        private static float GetBaseYawDegrees(PieceColor orientation) =>
            orientation == PieceColor.White ? 0.0f : 180.0f;
    }
}
