#if UNITY_EDITOR
using StillChess.Board.Board;
using StillChess.Board.CameraControl;
using StillChess.Board.Interaction;
using StillChess.Board.Pieces;
using StillChess.Board.Rendering;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace StillChess.Board.EditorTools
{
    /// <summary>
    /// Editor utility to populate or rebuild the 3D chessboard scene in Edit Mode
    /// and save <c>Assets/Scenes/ChessBoard.unity</c>.
    /// </summary>
    public static class ChessSceneSetupEditor
    {
        private const string ScenePath = "Assets/Scenes/ChessBoard.unity";

        [MenuItem("Tools/Still Chess/Rebuild 3D Chess Scene")]
        public static void RebuildSceneInEditor()
        {
            Camera mainCamera = Camera.main;
            if (mainCamera == null)
            {
                var camObj = new GameObject("Main Camera");
                camObj.tag = "MainCamera";
                mainCamera = camObj.AddComponent<Camera>();
                camObj.AddComponent<AudioListener>();
            }

            var cameraController = mainCamera.GetComponent<ChessCameraController>();
            if (cameraController == null)
            {
                cameraController = mainCamera.gameObject.AddComponent<ChessCameraController>();
            }

            cameraController.ApplyCameraTransform();

            GameObject boardRoot = GameObject.Find("ChessBoardRoot");
            if (boardRoot == null)
            {
                boardRoot = new GameObject("ChessBoardRoot");
            }

            if (boardRoot.GetComponent<ChessBoardGenerator>() == null)
            {
                boardRoot.AddComponent<ChessBoardGenerator>();
            }

            if (boardRoot.GetComponent<PieceFactory>() == null)
            {
                boardRoot.AddComponent<PieceFactory>();
            }

            var boardRenderer = boardRoot.GetComponent<BoardRenderer>();
            if (boardRenderer == null)
            {
                boardRenderer = boardRoot.AddComponent<BoardRenderer>();
            }

            if (boardRoot.GetComponent<BoardTouchRaycaster>() == null)
            {
                boardRoot.AddComponent<BoardTouchRaycaster>();
            }

            boardRenderer.InitializeDefaultPosition();
            EditorSceneManager.MarkSceneDirty(boardRoot.scene);
            Debug.Log("[Still Chess] Rebuilt 8x8 chessboard and 32 initial pieces from standard FEN.");
        }
    }
}
#endif

