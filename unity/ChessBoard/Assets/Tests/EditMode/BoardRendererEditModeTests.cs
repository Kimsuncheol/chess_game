using NUnit.Framework;
using StillChess.Board.Board;
using StillChess.Board.Core;
using StillChess.Board.Pieces;
using StillChess.Board.Rendering;
using UnityEngine;

namespace StillChess.Board.Tests
{
    public sealed class BoardRendererEditModeTests
    {
        private GameObject _rootObject;
        private BoardRenderer _boardRenderer;

        [SetUp]
        public void SetUp()
        {
            _rootObject = new GameObject("TestChessBoardRoot");
            _boardRenderer = _rootObject.AddComponent<BoardRenderer>();
            _boardRenderer.InitializeDefaultPosition();
        }

        [TearDown]
        public void TearDown()
        {
            if (_rootObject != null)
            {
                Object.DestroyImmediate(_rootObject);
            }
        }

        [Test]
        public void CoordinateMapping_MapsA1ThroughH8AndAlternatesColors()
        {
            SquareCoord a1 = SquareCoord.Parse("a1");
            SquareCoord b1 = SquareCoord.Parse("b1");
            SquareCoord h1 = SquareCoord.Parse("h1");
            SquareCoord a8 = SquareCoord.Parse("a8");
            SquareCoord h8 = SquareCoord.Parse("h8");

            Assert.That(a1.File, Is.EqualTo(0));
            Assert.That(a1.Rank, Is.EqualTo(0));
            Assert.That(a1.IsLightSquare, Is.False, "a1 must be a dark square.");
            Assert.That(b1.IsLightSquare, Is.True, "b1 must be a light square.");
            Assert.That(h1.IsLightSquare, Is.True, "h1 must be a light square.");
            Assert.That(a8.IsLightSquare, Is.True, "a8 must be a light square.");
            Assert.That(h8.IsLightSquare, Is.False, "h8 must be a dark square.");

            for (int rank = 0; rank < SquareCoord.BoardDimension; rank++)
            {
                for (int file = 0; file < SquareCoord.BoardDimension; file++)
                {
                    var expected = new SquareCoord(file, rank);
                    Vector3 world = expected.ToLocalPosition(1.0f);
                    bool found = SquareCoord.TryFromLocalPosition(world, 1.0f, out SquareCoord roundTrip);
                    Assert.That(found, Is.True);
                    Assert.That(roundTrip, Is.EqualTo(expected));
                }
            }
        }

        [Test]
        public void GenerateBoard_Creates64SquaresWithAlternatingSharedMaterials()
        {
            Assert.That(_boardRenderer.BoardGenerator.Squares.Count, Is.EqualTo(64));

            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("a1", out ChessSquareView a1View), Is.True);
            Assert.That(_boardRenderer.BoardGenerator.TryGetSquareView("b1", out ChessSquareView b1View), Is.True);
            Assert.That(a1View.IsLightSquare, Is.False);
            Assert.That(b1View.IsLightSquare, Is.True);

            var a1Renderer = a1View.GetComponent<MeshRenderer>();
            var b1Renderer = b1View.GetComponent<MeshRenderer>();
            Assert.That(a1Renderer.sharedMaterial, Is.Not.EqualTo(b1Renderer.sharedMaterial));
        }

        [Test]
        public void InitializeDefaultPosition_Creates32PiecesWithDistinctWhiteAndBlackMaterials()
        {
            Assert.That(_boardRenderer.PiecesBySquare.Count, Is.EqualTo(32));

            int whiteCount = 0;
            int blackCount = 0;
            foreach (ChessPieceView piece in _boardRenderer.PiecesBySquare.Values)
            {
                if (piece.Color == PieceColor.White)
                {
                    whiteCount++;
                }
                else
                {
                    blackCount++;
                }
            }

            Assert.That(whiteCount, Is.EqualTo(16));
            Assert.That(blackCount, Is.EqualTo(16));

            Assert.That(_boardRenderer.TryGetPieceAt("e1", out ChessPieceView whiteKing), Is.True);
            Assert.That(whiteKing.Color, Is.EqualTo(PieceColor.White));
            Assert.That(whiteKing.Type, Is.EqualTo(PieceType.King));

            Assert.That(_boardRenderer.TryGetPieceAt("d8", out ChessPieceView blackQueen), Is.True);
            Assert.That(blackQueen.Color, Is.EqualTo(PieceColor.Black));
            Assert.That(blackQueen.Type, Is.EqualTo(PieceType.Queen));

            Assert.That(
                _boardRenderer.MaterialPalette.WhitePiecePrimaryMaterial.color,
                Is.Not.EqualTo(_boardRenderer.MaterialPalette.BlackPiecePrimaryMaterial.color));
        }

        [Test]
        public void TryApplyFenSnapshot_ReconstructsArbitraryPositionAndRejectsInvalidFenWithoutMutatingBoard()
        {
            const string italianGameFen =
                "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4";

            bool applied = _boardRenderer.TryApplyFenSnapshot(italianGameFen, out string error);
            Assert.That(applied, Is.True, error);
            Assert.That(_boardRenderer.CurrentFen, Is.EqualTo(italianGameFen));
            Assert.That(_boardRenderer.PiecesBySquare.Count, Is.EqualTo(32));
            Assert.That(_boardRenderer.TryGetPieceAt("c4", out ChessPieceView whiteBishop), Is.True);
            Assert.That(whiteBishop.Type, Is.EqualTo(PieceType.Bishop));
            Assert.That(whiteBishop.Color, Is.EqualTo(PieceColor.White));
            Assert.That(_boardRenderer.TryGetPieceAt("c5", out ChessPieceView blackBishop), Is.True);
            Assert.That(blackBishop.Type, Is.EqualTo(PieceType.Bishop));
            Assert.That(blackBishop.Color, Is.EqualTo(PieceColor.Black));
            Assert.That(_boardRenderer.TryGetPieceAt("f1", out _), Is.False);

            // Invalid FEN must be rejected without clearing or corrupting the existing board.
            bool rejected = _boardRenderer.TryApplyFenSnapshot("invalid/fen/string", out string rejectError);
            Assert.That(rejected, Is.False);
            Assert.That(rejectError, Is.Not.Empty);
            Assert.That(_boardRenderer.CurrentFen, Is.EqualTo(italianGameFen));
            Assert.That(_boardRenderer.TryGetPieceAt("c4", out _), Is.True);
        }
    }
}

