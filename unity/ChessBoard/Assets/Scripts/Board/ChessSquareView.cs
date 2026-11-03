using StillChess.Board.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace StillChess.Board.Board
{
    public enum SquareHighlightState
    {
        None = 0,
        Selected = 1,
        LegalQuiet = 2,
        LegalCapture = 3,
    }

    /// <summary>
    /// Lightweight component attached to each generated board tile (<c>Square_a1</c> .. <c>Square_h8</c>)
    /// to support fast raycast lookup and visual highlight state presentation.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class ChessSquareView : MonoBehaviour
    {
        [SerializeField] private int file;
        [SerializeField] private int rank;
        [SerializeField] private string algebraic;
        [SerializeField] private bool isLightSquare;
        [SerializeField] private SquareHighlightState highlightState = SquareHighlightState.None;

        private MeshRenderer _meshRenderer;
        private Material _defaultMaterial;
        private GameObject _highlightMarker;
        private MeshRenderer _highlightMarkerRenderer;

        public SquareCoord Coordinate => new SquareCoord(file, rank);
        public string Algebraic => algebraic;
        public bool IsLightSquare => isLightSquare;
        public SquareHighlightState HighlightState => highlightState;
        public bool IsHighlighted => highlightState != SquareHighlightState.None;

        public void Initialize(SquareCoord coord, MeshRenderer meshRenderer, Material defaultMaterial)
        {
            file = coord.File;
            rank = coord.Rank;
            algebraic = coord.Algebraic;
            isLightSquare = coord.IsLightSquare;
            highlightState = SquareHighlightState.None;
            _meshRenderer = meshRenderer;
            _defaultMaterial = defaultMaterial;
            _meshRenderer.sharedMaterial = defaultMaterial;
            CreateHighlightMarker();
        }

        public void ApplyHighlight(SquareHighlightState state, Material highlightMaterial)
        {
            highlightState = state;
            if (_meshRenderer == null)
            {
                _meshRenderer = GetComponent<MeshRenderer>();
            }

            if (_meshRenderer != null)
            {
                _meshRenderer.sharedMaterial =
                    state != SquareHighlightState.None && highlightMaterial != null
                        ? highlightMaterial
                        : _defaultMaterial;
            }

            UpdateHighlightMarker(state, highlightMaterial);
        }

        public void SetHighlightMaterial(Material highlightMaterial)
        {
            ApplyHighlight(
                highlightMaterial != null ? SquareHighlightState.Selected : SquareHighlightState.None,
                highlightMaterial);
        }

        public void ResetMaterial() => ApplyHighlight(SquareHighlightState.None, null);

        private void CreateHighlightMarker()
        {
            if (_highlightMarker != null)
            {
                return;
            }

            _highlightMarker = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            _highlightMarker.name = $"HighlightMarker_{algebraic}";

            Collider markerCollider = _highlightMarker.GetComponent<Collider>();
            if (markerCollider != null)
            {
                if (Application.isPlaying)
                {
                    Destroy(markerCollider);
                }
                else
                {
                    DestroyImmediate(markerCollider);
                }
            }

            Transform markerTransform = _highlightMarker.transform;
            markerTransform.SetParent(transform, false);
            markerTransform.localPosition = new Vector3(0.0f, 0.52f, 0.0f);
            markerTransform.localRotation = Quaternion.identity;
            markerTransform.localScale = new Vector3(0.32f, 0.02f, 0.32f);

            _highlightMarkerRenderer = _highlightMarker.GetComponent<MeshRenderer>();
            _highlightMarkerRenderer.shadowCastingMode = ShadowCastingMode.Off;
            _highlightMarkerRenderer.receiveShadows = false;
            _highlightMarkerRenderer.lightProbeUsage = LightProbeUsage.Off;
            _highlightMarkerRenderer.reflectionProbeUsage = ReflectionProbeUsage.Off;

            _highlightMarker.SetActive(false);
        }

        private void UpdateHighlightMarker(SquareHighlightState state, Material highlightMaterial)
        {
            if (_highlightMarker == null)
            {
                CreateHighlightMarker();
            }

            if (state == SquareHighlightState.None || highlightMaterial == null)
            {
                _highlightMarker.SetActive(false);
                return;
            }

            // Quiet moves display a compact center dot; selected and capture squares display a broader ring disc.
            float diameter = state == SquareHighlightState.LegalQuiet ? 0.32f : 0.78f;
            _highlightMarker.transform.localScale = new Vector3(diameter, 0.025f, diameter);
            _highlightMarkerRenderer.sharedMaterial = highlightMaterial;
            _highlightMarker.SetActive(true);
        }
    }
}
