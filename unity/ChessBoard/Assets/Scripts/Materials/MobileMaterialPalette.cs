using System;
using StillChess.Board.Core;
using UnityEngine;

namespace StillChess.Board.Materials
{
    /// <summary>
    /// Shared, mobile-optimized material palette with GPU instancing enabled so all 64 squares
    /// and 32 pieces batch cleanly without per-object material allocations.
    /// </summary>
    public sealed class MobileMaterialPalette : IDisposable
    {
        // Board colors: warm maple light squares & walnut slate dark squares (a1 is dark).
        public static readonly Color DefaultLightSquareColor = new Color(0.91f, 0.87f, 0.79f, 1.0f);
        public static readonly Color DefaultDarkSquareColor = new Color(0.36f, 0.29f, 0.24f, 1.0f);
        public static readonly Color DefaultBoardFrameColor = new Color(0.19f, 0.16f, 0.14f, 1.0f);

        // Visually distinct piece colors with high contrast for mobile readability.
        public static readonly Color DefaultWhitePieceColor = new Color(0.96f, 0.94f, 0.89f, 1.0f);
        public static readonly Color DefaultWhitePieceAccentColor = new Color(0.82f, 0.77f, 0.68f, 1.0f);
        public static readonly Color DefaultBlackPieceColor = new Color(0.15f, 0.17f, 0.20f, 1.0f);
        public static readonly Color DefaultBlackPieceAccentColor = new Color(0.28f, 0.31f, 0.36f, 1.0f);

        // Highlight colors.
        public static readonly Color DefaultSelectedSquareColor = new Color(0.84f, 0.68f, 0.31f, 1.0f);
        public static readonly Color DefaultLegalMoveSquareColor = new Color(0.42f, 0.67f, 0.49f, 1.0f);
        public static readonly Color DefaultLegalCaptureSquareColor = new Color(0.84f, 0.44f, 0.36f, 1.0f);

        public Material LightSquareMaterial { get; }
        public Material DarkSquareMaterial { get; }
        public Material BoardFrameMaterial { get; }
        public Material WhitePiecePrimaryMaterial { get; }
        public Material WhitePieceAccentMaterial { get; }
        public Material BlackPiecePrimaryMaterial { get; }
        public Material BlackPieceAccentMaterial { get; }
        public Material SelectedSquareMaterial { get; }
        public Material LegalMoveSquareMaterial { get; }
        public Material LegalCaptureSquareMaterial { get; }

        public MobileMaterialPalette()
        {
            Shader shader = ResolveMobileShader();

            LightSquareMaterial = CreateSharedMaterial("Mat_Square_Light", shader, DefaultLightSquareColor, smoothness: 0.15f);
            DarkSquareMaterial = CreateSharedMaterial("Mat_Square_Dark", shader, DefaultDarkSquareColor, smoothness: 0.15f);
            BoardFrameMaterial = CreateSharedMaterial("Mat_Board_Frame", shader, DefaultBoardFrameColor, smoothness: 0.10f);

            WhitePiecePrimaryMaterial = CreateSharedMaterial("Mat_Piece_White_Primary", shader, DefaultWhitePieceColor, smoothness: 0.35f);
            WhitePieceAccentMaterial = CreateSharedMaterial("Mat_Piece_White_Accent", shader, DefaultWhitePieceAccentColor, smoothness: 0.40f);
            BlackPiecePrimaryMaterial = CreateSharedMaterial("Mat_Piece_Black_Primary", shader, DefaultBlackPieceColor, smoothness: 0.45f);
            BlackPieceAccentMaterial = CreateSharedMaterial("Mat_Piece_Black_Accent", shader, DefaultBlackPieceAccentColor, smoothness: 0.50f);

            SelectedSquareMaterial = CreateSharedMaterial("Mat_Square_Selected", shader, DefaultSelectedSquareColor, smoothness: 0.25f);
            LegalMoveSquareMaterial = CreateSharedMaterial("Mat_Square_LegalMove", shader, DefaultLegalMoveSquareColor, smoothness: 0.25f);
            LegalCaptureSquareMaterial = CreateSharedMaterial("Mat_Square_LegalCapture", shader, DefaultLegalCaptureSquareColor, smoothness: 0.25f);
        }

        public Material GetSquareMaterial(SquareCoord square) =>
            square.IsLightSquare ? LightSquareMaterial : DarkSquareMaterial;

        public Material GetPiecePrimaryMaterial(PieceColor color) =>
            color == PieceColor.White ? WhitePiecePrimaryMaterial : BlackPiecePrimaryMaterial;

        public Material GetPieceAccentMaterial(PieceColor color) =>
            color == PieceColor.White ? WhitePieceAccentMaterial : BlackPieceAccentMaterial;

        private static Shader ResolveMobileShader()
        {
            string[] candidates =
            {
                "Universal Render Pipeline/Simple Lit",
                "Universal Render Pipeline/Lit",
                "Mobile/Diffuse",
                "Standard",
                "Sprites/Default",
            };

            for (int i = 0; i < candidates.Length; i++)
            {
                Shader found = Shader.Find(candidates[i]);
                if (found != null)
                {
                    return found;
                }
            }

            return Shader.Find("Hidden/InternalErrorShader");
        }

        private static Material CreateSharedMaterial(string name, Shader shader, Color color, float smoothness)
        {
            var material = new Material(shader)
            {
                name = name,
                color = color,
                enableInstancing = true,
            };

            if (material.HasProperty("_BaseColor"))
            {
                material.SetColor("_BaseColor", color);
            }

            if (material.HasProperty("_Color"))
            {
                material.SetColor("_Color", color);
            }

            if (material.HasProperty("_Smoothness"))
            {
                material.SetFloat("_Smoothness", smoothness);
            }

            if (material.HasProperty("_Glossiness"))
            {
                material.SetFloat("_Glossiness", smoothness);
            }

            return material;
        }

        public void Dispose()
        {
            DestroyMaterial(LightSquareMaterial);
            DestroyMaterial(DarkSquareMaterial);
            DestroyMaterial(BoardFrameMaterial);
            DestroyMaterial(WhitePiecePrimaryMaterial);
            DestroyMaterial(WhitePieceAccentMaterial);
            DestroyMaterial(BlackPiecePrimaryMaterial);
            DestroyMaterial(BlackPieceAccentMaterial);
            DestroyMaterial(SelectedSquareMaterial);
            DestroyMaterial(LegalMoveSquareMaterial);
            DestroyMaterial(LegalCaptureSquareMaterial);
        }

        private static void DestroyMaterial(Material material)
        {
            if (material == null)
            {
                return;
            }

            if (Application.isPlaying)
            {
                UnityEngine.Object.Destroy(material);
            }
            else
            {
                UnityEngine.Object.DestroyImmediate(material);
            }
        }
    }
}

