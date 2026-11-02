using StillChess.Board.Core;
using StillChess.Board.Materials;
using UnityEngine;
using UnityEngine.Rendering;

namespace StillChess.Board.Pieces
{
    /// <summary>
    /// Creates lightweight, mobile-optimized 3D placeholder hierarchies for the six standard chess piece types
    /// (<see cref="PieceType.Pawn"/>, <see cref="PieceType.Knight"/>, <see cref="PieceType.Bishop"/>,
    /// <see cref="PieceType.Rook"/>, <see cref="PieceType.Queen"/>, and <see cref="PieceType.King"/>).
    /// <para>
    /// All primitives share Unity's built-in primitive meshes and GPU-instanced materials from
    /// <see cref="MobileMaterialPalette"/>, with child colliders removed for low mobile CPU/GPU overhead.
    /// </para>
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class PieceFactory : MonoBehaviour
    {
        public ChessPieceView CreatePiece(
            PlacedPieceData data,
            Transform parent,
            Vector3 localPosition,
            MobileMaterialPalette palette)
        {
            var root = new GameObject($"Piece_{data.FenChar}_{data.Square.Algebraic}");
            Transform rootTransform = root.transform;
            rootTransform.SetParent(parent, false);

            Material primary = palette.GetPiecePrimaryMaterial(data.Color);
            Material accent = palette.GetPieceAccentMaterial(data.Color);

            // Common circular pedestal base for every piece.
            AddPart(
                rootTransform,
                "Base",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.04f, 0.0f),
                new Vector3(0.66f, 0.04f, 0.66f),
                Quaternion.identity,
                primary);

            AddPart(
                rootTransform,
                "BaseCollar",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.095f, 0.0f),
                new Vector3(0.52f, 0.02f, 0.52f),
                Quaternion.identity,
                accent);

            switch (data.Type)
            {
                case PieceType.Pawn:
                    BuildPawn(rootTransform, primary, accent);
                    break;
                case PieceType.Rook:
                    BuildRook(rootTransform, primary, accent);
                    break;
                case PieceType.Knight:
                    BuildKnight(rootTransform, primary, accent);
                    break;
                case PieceType.Bishop:
                    BuildBishop(rootTransform, primary, accent);
                    break;
                case PieceType.Queen:
                    BuildQueen(rootTransform, primary, accent);
                    break;
                case PieceType.King:
                    BuildKing(rootTransform, primary, accent);
                    break;
            }

            var pieceView = root.AddComponent<ChessPieceView>();
            pieceView.Initialize(data, localPosition);
            return pieceView;
        }

        private static void BuildPawn(Transform root, Material primary, Material accent)
        {
            AddPart(
                root,
                "Stem",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.22f, 0.0f),
                new Vector3(0.30f, 0.11f, 0.30f),
                Quaternion.identity,
                primary);

            AddPart(
                root,
                "Collar",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.34f, 0.0f),
                new Vector3(0.36f, 0.015f, 0.36f),
                Quaternion.identity,
                accent);

            AddPart(
                root,
                "Head",
                PrimitiveType.Sphere,
                new Vector3(0.0f, 0.45f, 0.0f),
                new Vector3(0.28f, 0.28f, 0.28f),
                Quaternion.identity,
                primary);
        }

        private static void BuildRook(Transform root, Material primary, Material accent)
        {
            AddPart(
                root,
                "TowerColumn",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.29f, 0.0f),
                new Vector3(0.42f, 0.18f, 0.42f),
                Quaternion.identity,
                primary);

            AddPart(
                root,
                "BattlementRim",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.50f, 0.0f),
                new Vector3(0.48f, 0.05f, 0.48f),
                Quaternion.identity,
                accent);

            AddPart(
                root,
                "CrestBlock",
                PrimitiveType.Cube,
                new Vector3(0.0f, 0.57f, 0.0f),
                new Vector3(0.34f, 0.08f, 0.34f),
                Quaternion.identity,
                primary);
        }

        private static void BuildKnight(Transform root, Material primary, Material accent)
        {
            AddPart(
                root,
                "Neck",
                PrimitiveType.Cube,
                new Vector3(0.0f, 0.30f, -0.02f),
                new Vector3(0.26f, 0.38f, 0.32f),
                Quaternion.Euler(-14.0f, 0.0f, 0.0f),
                primary);

            AddPart(
                root,
                "HeadMuzzle",
                PrimitiveType.Cube,
                new Vector3(0.0f, 0.50f, 0.10f),
                new Vector3(0.22f, 0.18f, 0.34f),
                Quaternion.Euler(18.0f, 0.0f, 0.0f),
                primary);

            AddPart(
                root,
                "ManeCrest",
                PrimitiveType.Cube,
                new Vector3(0.0f, 0.43f, -0.14f),
                new Vector3(0.10f, 0.32f, 0.10f),
                Quaternion.Euler(-12.0f, 0.0f, 0.0f),
                accent);
        }

        private static void BuildBishop(Transform root, Material primary, Material accent)
        {
            AddPart(
                root,
                "Stem",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.28f, 0.0f),
                new Vector3(0.30f, 0.17f, 0.30f),
                Quaternion.identity,
                primary);

            AddPart(
                root,
                "Collar",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.46f, 0.0f),
                new Vector3(0.38f, 0.02f, 0.38f),
                Quaternion.identity,
                accent);

            AddPart(
                root,
                "Mitre",
                PrimitiveType.Capsule,
                new Vector3(0.0f, 0.58f, 0.0f),
                new Vector3(0.28f, 0.16f, 0.28f),
                Quaternion.identity,
                primary);

            AddPart(
                root,
                "Finial",
                PrimitiveType.Sphere,
                new Vector3(0.0f, 0.74f, 0.0f),
                new Vector3(0.10f, 0.10f, 0.10f),
                Quaternion.identity,
                accent);
        }

        private static void BuildQueen(Transform root, Material primary, Material accent)
        {
            AddPart(
                root,
                "Column",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.34f, 0.0f),
                new Vector3(0.34f, 0.23f, 0.34f),
                Quaternion.identity,
                primary);

            AddPart(
                root,
                "CoronetRing",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.60f, 0.0f),
                new Vector3(0.46f, 0.04f, 0.46f),
                Quaternion.identity,
                accent);

            AddPart(
                root,
                "CrownDome",
                PrimitiveType.Sphere,
                new Vector3(0.0f, 0.70f, 0.0f),
                new Vector3(0.30f, 0.22f, 0.30f),
                Quaternion.identity,
                primary);

            AddPart(
                root,
                "CrownOrb",
                PrimitiveType.Sphere,
                new Vector3(0.0f, 0.83f, 0.0f),
                new Vector3(0.12f, 0.12f, 0.12f),
                Quaternion.identity,
                accent);
        }

        private static void BuildKing(Transform root, Material primary, Material accent)
        {
            AddPart(
                root,
                "Column",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.36f, 0.0f),
                new Vector3(0.36f, 0.25f, 0.36f),
                Quaternion.identity,
                primary);

            AddPart(
                root,
                "RoyalCollar",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.64f, 0.0f),
                new Vector3(0.48f, 0.045f, 0.48f),
                Quaternion.identity,
                accent);

            AddPart(
                root,
                "CrownMiter",
                PrimitiveType.Cylinder,
                new Vector3(0.0f, 0.73f, 0.0f),
                new Vector3(0.34f, 0.06f, 0.34f),
                Quaternion.identity,
                primary);

            AddPart(
                root,
                "CrossVertical",
                PrimitiveType.Cube,
                new Vector3(0.0f, 0.88f, 0.0f),
                new Vector3(0.07f, 0.18f, 0.07f),
                Quaternion.identity,
                accent);

            AddPart(
                root,
                "CrossHorizontal",
                PrimitiveType.Cube,
                new Vector3(0.0f, 0.90f, 0.0f),
                new Vector3(0.18f, 0.06f, 0.07f),
                Quaternion.identity,
                accent);
        }

        private static void AddPart(
            Transform parent,
            string partName,
            PrimitiveType primitiveType,
            Vector3 localPosition,
            Vector3 localScale,
            Quaternion localRotation,
            Material sharedMaterial)
        {
            GameObject part = GameObject.CreatePrimitive(primitiveType);
            part.name = partName;

            Collider collider = part.GetComponent<Collider>();
            if (collider != null)
            {
                if (Application.isPlaying)
                {
                    Destroy(collider);
                }
                else
                {
                    DestroyImmediate(collider);
                }
            }

            Transform partTransform = part.transform;
            partTransform.SetParent(parent, false);
            partTransform.localPosition = localPosition;
            partTransform.localRotation = localRotation;
            partTransform.localScale = localScale;

            var meshRenderer = part.GetComponent<MeshRenderer>();
            meshRenderer.sharedMaterial = sharedMaterial;
            meshRenderer.shadowCastingMode = ShadowCastingMode.On;
            meshRenderer.receiveShadows = true;
            meshRenderer.lightProbeUsage = LightProbeUsage.Off;
            meshRenderer.reflectionProbeUsage = ReflectionProbeUsage.Off;
        }
    }
}

