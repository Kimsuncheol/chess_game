using StillChess.Board.Core;
using UnityEngine;

namespace StillChess.Board.CameraControl
{
    /// <summary>
    /// Mobile-friendly perspective camera controller for the 3D chessboard.
    /// Supports White and Black player perspectives and bounded camera reset.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class ChessCameraController : MonoBehaviour
    {
        [SerializeField] private Vector3 boardTarget = new Vector3(0.0f, 0.1f, 0.0f);
        [SerializeField] private float defaultDistance = 10.2f;
        [SerializeField] private float defaultPitchDegrees = 52.0f;
        [SerializeField] private PieceColor currentOrientation = PieceColor.White;

        public PieceColor CurrentOrientation => currentOrientation;

        private void Awake()
        {
            ApplyCameraTransform();
        }

        public void SetOrientation(PieceColor orientation)
        {
            currentOrientation = orientation;
            ApplyCameraTransform();
        }

        public void ResetCamera()
        {
            ApplyCameraTransform();
        }

        public void ApplyCameraTransform()
        {
            float yawDegrees = currentOrientation == PieceColor.White ? 0.0f : 180.0f;
            float pitchRad = defaultPitchDegrees * Mathf.Deg2Rad;
            float yawRad = yawDegrees * Mathf.Deg2Rad;

            float horizontalRadius = Mathf.Cos(pitchRad) * defaultDistance;
            float height = Mathf.Sin(pitchRad) * defaultDistance;

            var offset = new Vector3(
                -Mathf.Sin(yawRad) * horizontalRadius,
                height,
                -Mathf.Cos(yawRad) * horizontalRadius);

            transform.position = boardTarget + offset;
            transform.LookAt(boardTarget, Vector3.up);
        }
    }
}

