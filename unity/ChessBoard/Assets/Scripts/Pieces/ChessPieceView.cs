using StillChess.Board.Core;
using UnityEngine;

namespace StillChess.Board.Pieces
{
    /// <summary>
    /// Presentation metadata attached to an instantiated 3D chess piece on the board.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class ChessPieceView : MonoBehaviour
    {
        [SerializeField] private string squareAlgebraic;
        [SerializeField] private PieceColor pieceColor;
        [SerializeField] private PieceType pieceType;
        [SerializeField] private char fenChar;

        public SquareCoord Square { get; private set; }
        public string SquareAlgebraic => squareAlgebraic;
        public PieceColor Color => pieceColor;
        public PieceType Type => pieceType;
        public char FenChar => fenChar;

        public void Initialize(PlacedPieceData data, Vector3 localPosition)
        {
            Square = data.Square;
            squareAlgebraic = data.Square.Algebraic;
            pieceColor = data.Color;
            pieceType = data.Type;
            fenChar = data.FenChar;

            transform.localPosition = localPosition;
            // Knights and asymmetric silhouettes face toward the opponent's back rank.
            float yaw = data.Color == PieceColor.White ? 0.0f : 180.0f;
            transform.localRotation = Quaternion.Euler(0.0f, yaw, 0.0f);
        }
    }
}

