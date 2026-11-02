using System;
using UnityEngine;

namespace StillChess.Board.Core
{
    /// <summary>
    /// Immutable coordinate mapping between standard algebraic chess notation
    /// (<c>a1</c> through <c>h8</c>), 0-indexed file/rank coordinates, and Unity 3D world space.
    /// <para>
    /// File <c>a..h</c> maps to <c>0..7</c> along the positive X axis;
    /// Rank <c>1..8</c> maps to <c>0..7</c> along the positive Z axis.
    /// By standard chess rules, <c>a1</c> (file 0, rank 0) is a dark square.
    /// </para>
    /// </summary>
    [Serializable]
    public readonly struct SquareCoord : IEquatable<SquareCoord>
    {
        public const int BoardDimension = 8;
        public const int TotalSquares = BoardDimension * BoardDimension;

        /// <summary>0-based file index (<c>0 = 'a'</c> .. <c>7 = 'h'</c>).</summary>
        public readonly int File;

        /// <summary>0-based rank index (<c>0 = '1'</c> .. <c>7 = '8'</c>).</summary>
        public readonly int Rank;

        public SquareCoord(int file, int rank)
        {
            if (file < 0 || file >= BoardDimension)
            {
                throw new ArgumentOutOfRangeException(nameof(file), "File must be in range 0..7 (a..h).");
            }

            if (rank < 0 || rank >= BoardDimension)
            {
                throw new ArgumentOutOfRangeException(nameof(rank), "Rank must be in range 0..7 (1..8).");
            }

            File = file;
            Rank = rank;
        }

        /// <summary>Lowercase algebraic square identifier (<c>a1</c> through <c>h8</c>).</summary>
        public string Algebraic => $"{(char)('a' + File)}{(char)('1' + Rank)}";

        /// <summary>
        /// True when the square is light-colored; false when dark-colored.
        /// <c>a1</c> (0, 0) is dark, <c>b1</c> (1, 0) is light, <c>h1</c> (7, 0) is light, and <c>a8</c> (0, 7) is light.
        /// </summary>
        public bool IsLightSquare => ((File + Rank) & 1) == 1;

        /// <summary>Linear index in <c>0..63</c> ordered rank-major from <c>a1</c> (0) to <c>h8</c> (63).</summary>
        public int Index => (Rank * BoardDimension) + File;

        public static bool TryParse(string algebraic, out SquareCoord square)
        {
            square = default;
            if (string.IsNullOrEmpty(algebraic) || algebraic.Length != 2)
            {
                return false;
            }

            char fileChar = algebraic[0];
            char rankChar = algebraic[1];
            if (fileChar < 'a' || fileChar > 'h' || rankChar < '1' || rankChar > '8')
            {
                return false;
            }

            square = new SquareCoord(fileChar - 'a', rankChar - '1');
            return true;
        }

        public static SquareCoord Parse(string algebraic)
        {
            if (!TryParse(algebraic, out SquareCoord square))
            {
                throw new ArgumentException(
                    $"Invalid algebraic square '{algebraic}'. Expected 'a1' through 'h8'.",
                    nameof(algebraic));
            }

            return square;
        }

        /// <summary>
        /// Converts this square to a board-local 3D position centered around <c>(0, yOffset, 0)</c>.
        /// <c>a1</c> is at <c>(-3.5 * squareSize, yOffset, -3.5 * squareSize)</c> and
        /// <c>h8</c> is at <c>(+3.5 * squareSize, yOffset, +3.5 * squareSize)</c>.
        /// </summary>
        public Vector3 ToLocalPosition(float squareSize = 1.0f, float yOffset = 0.0f)
        {
            float halfBoardOffset = (BoardDimension - 1) * 0.5f;
            float x = (File - halfBoardOffset) * squareSize;
            float z = (Rank - halfBoardOffset) * squareSize;
            return new Vector3(x, yOffset, z);
        }

        /// <summary>
        /// Converts a board-local 3D point back into a <see cref="SquareCoord"/> if it lies within the 8x8 grid.
        /// </summary>
        public static bool TryFromLocalPosition(Vector3 localPosition, float squareSize, out SquareCoord square)
        {
            square = default;
            if (squareSize <= 0.0f)
            {
                return false;
            }

            float halfBoardSpan = BoardDimension * 0.5f * squareSize;
            if (localPosition.x < -halfBoardSpan || localPosition.x >= halfBoardSpan ||
                localPosition.z < -halfBoardSpan || localPosition.z >= halfBoardSpan)
            {
                return false;
            }

            int file = Mathf.FloorToInt((localPosition.x + halfBoardSpan) / squareSize);
            int rank = Mathf.FloorToInt((localPosition.z + halfBoardSpan) / squareSize);
            file = Mathf.Clamp(file, 0, BoardDimension - 1);
            rank = Mathf.Clamp(rank, 0, BoardDimension - 1);
            square = new SquareCoord(file, rank);
            return true;
        }

        public bool Equals(SquareCoord other) => File == other.File && Rank == other.Rank;

        public override bool Equals(object obj) => obj is SquareCoord other && Equals(other);

        public override int GetHashCode() => (Rank * BoardDimension) + File;

        public override string ToString() => Algebraic;

        public static bool operator ==(SquareCoord left, SquareCoord right) => left.Equals(right);

        public static bool operator !=(SquareCoord left, SquareCoord right) => !left.Equals(right);
    }
}

