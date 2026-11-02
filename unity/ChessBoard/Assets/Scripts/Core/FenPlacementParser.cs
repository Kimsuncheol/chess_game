using System;
using System.Collections.Generic;

namespace StillChess.Board.Core
{
    public enum PieceColor
    {
        White = 0,
        Black = 1,
    }

    public enum PieceType
    {
        Pawn = 0,
        Knight = 1,
        Bishop = 2,
        Rook = 3,
        Queen = 4,
        King = 5,
    }

    /// <summary>
    /// Presentation-only descriptor for a single piece placed on the 3D board from a FEN snapshot.
    /// </summary>
    [Serializable]
    public readonly struct PlacedPieceData : IEquatable<PlacedPieceData>
    {
        public readonly SquareCoord Square;
        public readonly PieceColor Color;
        public readonly PieceType Type;
        public readonly char FenChar;

        public PlacedPieceData(SquareCoord square, PieceColor color, PieceType type, char fenChar)
        {
            Square = square;
            Color = color;
            Type = type;
            FenChar = fenChar;
        }

        public bool Equals(PlacedPieceData other) =>
            Square.Equals(other.Square) &&
            Color == other.Color &&
            Type == other.Type &&
            FenChar == other.FenChar;

        public override bool Equals(object obj) => obj is PlacedPieceData other && Equals(other);

        public override int GetHashCode() => HashCode.Combine(Square, (int)Color, (int)Type, FenChar);
    }

    /// <summary>
    /// Structural parser for standard six-field FEN snapshots used to reconstruct the 3D board.
    /// <para>
    /// IMPORTANT: Unity is strictly a presentation client. This parser validates FEN structure and extracts
    /// square placement (<c>a1..h8</c>) for 3D rendering only; it intentionally implements zero chess rules,
    /// move legality, check detection, or game-result adjudication.
    /// </para>
    /// </summary>
    public static class FenPlacementParser
    {
        public const string StandardStartingFen =
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

        public static bool TryParseFen(
            string fen,
            out IReadOnlyList<PlacedPieceData> pieces,
            out PieceColor sideToMove,
            out string error)
        {
            pieces = Array.Empty<PlacedPieceData>();
            sideToMove = PieceColor.White;
            error = null;

            if (string.IsNullOrWhiteSpace(fen))
            {
                error = "FEN string must not be empty.";
                return false;
            }

            string[] fields = fen.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length != 6)
            {
                error = $"Expected a 6-field FEN string, but received {fields.Length} field(s).";
                return false;
            }

            string placementField = fields[0];
            string activeColorField = fields[1];
            string castlingField = fields[2];
            string enPassantField = fields[3];
            string halfmoveField = fields[4];
            string fullmoveField = fields[5];

            if (activeColorField == "w")
            {
                sideToMove = PieceColor.White;
            }
            else if (activeColorField == "b")
            {
                sideToMove = PieceColor.Black;
            }
            else
            {
                error = $"Invalid FEN active color '{activeColorField}'. Expected 'w' or 'b'.";
                return false;
            }

            if (!IsValidCastlingToken(castlingField))
            {
                error = $"Invalid FEN castling token '{castlingField}'.";
                return false;
            }

            if (!IsValidEnPassantToken(enPassantField))
            {
                error = $"Invalid FEN en-passant token '{enPassantField}'.";
                return false;
            }

            if (!int.TryParse(halfmoveField, out int halfmoveClock) || halfmoveClock < 0)
            {
                error = $"Invalid FEN halfmove clock '{halfmoveField}'.";
                return false;
            }

            if (!int.TryParse(fullmoveField, out int fullmoveNumber) || fullmoveNumber < 1)
            {
                error = $"Invalid FEN fullmove number '{fullmoveField}'.";
                return false;
            }

            string[] rankStrings = placementField.Split('/');
            if (rankStrings.Length != SquareCoord.BoardDimension)
            {
                error = $"Invalid FEN placement: expected 8 ranks, found {rankStrings.Length}.";
                return false;
            }

            var parsedPieces = new List<PlacedPieceData>(32);

            // FEN ranks are ordered from rank 8 (index 7) down to rank 1 (index 0).
            for (int fenRankIndex = 0; fenRankIndex < SquareCoord.BoardDimension; fenRankIndex++)
            {
                int boardRank = (SquareCoord.BoardDimension - 1) - fenRankIndex;
                string rankText = rankStrings[fenRankIndex];
                if (string.IsNullOrEmpty(rankText))
                {
                    error = $"FEN rank {boardRank + 1} is empty.";
                    return false;
                }

                int file = 0;
                for (int i = 0; i < rankText.Length; i++)
                {
                    char token = rankText[i];
                    if (token >= '1' && token <= '8')
                    {
                        file += token - '0';
                        if (file > SquareCoord.BoardDimension)
                        {
                            error = $"FEN rank {boardRank + 1} exceeds 8 files.";
                            return false;
                        }
                    }
                    else if (TryDecodePieceChar(token, out PieceColor color, out PieceType type))
                    {
                        if (file >= SquareCoord.BoardDimension)
                        {
                            error = $"FEN rank {boardRank + 1} exceeds 8 files.";
                            return false;
                        }

                        var square = new SquareCoord(file, boardRank);
                        parsedPieces.Add(new PlacedPieceData(square, color, type, token));
                        file++;
                    }
                    else
                    {
                        error = $"Invalid FEN piece character '{token}' on rank {boardRank + 1}.";
                        return false;
                    }
                }

                if (file != SquareCoord.BoardDimension)
                {
                    error = $"FEN rank {boardRank + 1} expanded to {file} file(s) instead of 8.";
                    return false;
                }
            }

            pieces = parsedPieces;
            return true;
        }

        public static bool TryDecodePieceChar(char fenChar, out PieceColor color, out PieceType type)
        {
            color = char.IsUpper(fenChar) ? PieceColor.White : PieceColor.Black;
            switch (char.ToLowerInvariant(fenChar))
            {
                case 'p':
                    type = PieceType.Pawn;
                    return true;
                case 'n':
                    type = PieceType.Knight;
                    return true;
                case 'b':
                    type = PieceType.Bishop;
                    return true;
                case 'r':
                    type = PieceType.Rook;
                    return true;
                case 'q':
                    type = PieceType.Queen;
                    return true;
                case 'k':
                    type = PieceType.King;
                    return true;
                default:
                    type = default;
                    return false;
            }
        }

        private static bool IsValidCastlingToken(string token)
        {
            if (token == "-")
            {
                return true;
            }

            if (string.IsNullOrEmpty(token) || token.Length > 4)
            {
                return false;
            }

            const string allowedOrder = "KQkq";
            int lastIndex = -1;
            for (int i = 0; i < token.Length; i++)
            {
                int idx = allowedOrder.IndexOf(token[i]);
                if (idx <= lastIndex)
                {
                    return false;
                }

                lastIndex = idx;
            }

            return true;
        }

        private static bool IsValidEnPassantToken(string token)
        {
            if (token == "-")
            {
                return true;
            }

            return SquareCoord.TryParse(token, out SquareCoord sq) && (sq.Rank == 2 || sq.Rank == 5);
        }
    }
}

