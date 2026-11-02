# Unity 3D Chess Scene (`unity/ChessBoard`)

This document describes the architecture, coordinate system, mobile optimizations, FEN snapshot reconstruction, and instructions for opening and running the Unity 3D chess project located in [`unity/ChessBoard`](../unity/ChessBoard).

---

## 1. Scene & Script Organization

```text
unity/ChessBoard/
├── Assets/
│   ├── Editor/
│   │   └── ChessSceneSetupEditor.cs        # Menu command: Tools > Still Chess > Rebuild 3D Chess Scene
│   ├── Scenes/
│   │   └── ChessBoard.unity                # Main 3D chessboard scene (Camera, Light, ChessBoardRoot)
│   ├── Scripts/
│   │   ├── ChessBoard.Runtime.asmdef       # Runtime assembly definition (StillChess.Board)
│   │   ├── Board/
│   │   │   ├── ChessBoardGenerator.cs      # Generates 64 squares (a1..h8) + board border frame
│   │   │   └── ChessSquareView.cs          # Per-square coordinate metadata & highlight material swapping
│   │   ├── Camera/
│   │   │   └── ChessCameraController.cs    # Bounded White/Black perspective camera & ResetCamera()
│   │   ├── Core/
│   │   │   ├── FenPlacementParser.cs       # Structural 6-field FEN parser (presentation only; zero chess rules)
│   │   │   └── SquareCoordinates.cs        # Algebraic a1..h8 <-> 0..7 file/rank <-> 3D local position mapping
│   │   ├── Interaction/
│   │   │   └── BoardTouchRaycaster.cs      # Mobile touch/mouse raycasting -> algebraic square intents
│   │   ├── Materials/
│   │   │   └── MobileMaterialPalette.cs    # Shared, GPU-instanced materials for squares, pieces, & highlights
│   │   ├── Pieces/
│   │   │   ├── ChessPieceView.cs           # Piece instance metadata (Square, PieceColor, PieceType, FenChar)
│   │   │   └── PieceFactory.cs             # Builds distinct low-poly placeholder hierarchies for P/N/B/R/Q/K
│   │   └── Rendering/
│   │       └── BoardRenderer.cs            # Reconstructs the 3D board atomically from FEN or bridge JSON snapshots
│   └── Tests/
│       └── EditMode/
│           ├── ChessBoard.EditorTests.asmdef
│           └── BoardRendererEditModeTests.cs
├── Packages/
│   └── manifest.json
└── ProjectSettings/
    ├── EditorBuildSettings.asset
    ├── ProjectSettings.asset
    ├── ProjectVersion.txt
    └── QualitySettings.asset
```

---

## 2. Coordinate Mapping (`a1` through `h8`)

`SquareCoord` (`Assets/Scripts/Core/SquareCoordinates.cs`) maps standard algebraic notation to 0-indexed coordinates and board-local 3D world space:

- **Files (`a`..`h`)**: Mapped to `File = 0..7` along the **+X** axis (`x = (File - 3.5) * squareSize`).
- **Ranks (`1`..`8`)**: Mapped to `Rank = 0..7` along the **+Z** axis (`z = (Rank - 3.5) * squareSize`).
- **Square Colors**: Determined by `IsLightSquare => ((File + Rank) & 1) == 1`:
  - `a1` (`0, 0`) is **dark** (`(-3.5, 0, -3.5)`).
  - `b1` (`1, 0`) and `h1` (`7, 0`) are **light**.
  - `a8` (`0, 7`) is **light**, and `h8` (`7, 7`) is **dark** (`(+3.5, 0, +3.5)`).
- **Camera Perspective**:
  - **White orientation**: Camera sits on the `-Z` side looking toward `+Z` (`a1` at bottom-left, `h1` at bottom-right).
  - **Black orientation**: Camera rotates `180°` around the board center to sit on the `+Z` side looking toward `-Z` (`h8` at bottom-left, `a8` at bottom-right).

---

## 3. Placeholder Piece Meshes & Visual Distinction

`PieceFactory` (`Assets/Scripts/Pieces/PieceFactory.cs`) constructs each of the six piece types from shared Unity primitive meshes (`Cylinder`, `Sphere`, `Cube`, `Capsule`) with distinct heights and silhouettes:

| Piece Type | FEN Codes | Silhouette Composition | Approx. Height |
| :--- | :--- | :--- | :--- |
| **Pawn** | `P` / `p` | Pedestal base, tapered stem, collar ring, spherical head | `0.52` units |
| **Rook** | `R` / `r` | Pedestal base, stout cylindrical tower, battlement crown block | `0.64` units |
| **Knight** | `N` / `n` | Pedestal base, angled neck, forward muzzle, mane crest (faces opponent) | `0.68` units |
| **Bishop** | `B` / `b` | Pedestal base, slender stem, collar, capsule mitre, top finial orb | `0.74` units |
| **Queen** | `Q` / `q` | Pedestal base, tall column, flared coronet ring, dome + crown orb | `0.84` units |
| **King** | `K` / `k` | Pedestal base, tall column, royal collar, miter + orthogonal cross | `0.94` units |

- **White vs. Black Distinction**: `MobileMaterialPalette` provides high-contrast warm alabaster ivory (`#F5F0E3` primary / `#D1C4AD` accent) for White pieces and deep obsidian charcoal (`#262B33` primary / `#474F5C` accent) for Black pieces.

---

## 4. Mobile Optimization & Presentation-Only Architecture

1. **Shared GPU-Instanced Materials**: `MobileMaterialPalette` creates a single set of shared `Material` instances with `enableInstancing = true` using mobile-friendly shaders (`Universal Render Pipeline/Simple Lit` or `Mobile/Diffuse` with `Standard` fallback). No per-square or per-piece material copies are allocated.
2. **Low Collider & Shadow Overhead**:
   - Child primitive parts on pieces have their `Collider` components stripped immediately; raycasting uses only the board tiles (`ChessSquareView`).
   - Board squares disable shadow casting (`ShadowCastingMode.Off`) and light/reflection probes (`LightProbeUsage.Off`, `ReflectionProbeUsage.Off`).
   - `QualitySettings.asset` uses a single directional light, medium hard shadows, and Android frame pacing (`androidUseSwappy: 1`).
3. **Zero Independent Chess Rules in Unity**:
   - In accordance with [`docs/unity_flutter_bridge.md`](unity_flutter_bridge.md), Unity never generates legal moves, checks turn order, or adjudicates checkmate/draw results.
   - `BoardRenderer.TryApplyFenSnapshot(string fen, out string error)` and `BoardRenderer.TryApplySnapshotJson(string json, out string error)` validate the incoming 6-field FEN structure first and atomically reconstruct all pieces from the FEN placement field. If a FEN string is malformed, the existing board visual state is preserved untouched.

---

## 5. How to Open and Run the Unity Project

### Prerequisites
- **Unity Hub** with **Unity 6000.3 LTS** (`6000.3.1f1` or newer 6000.3 patch) installed.
- **Android Build Support** module (including **Android SDK & NDK Tools** and **OpenJDK**) installed via Unity Hub for Android deployment.

### Step 1: Open in Unity Editor
1. Open **Unity Hub**.
2. Click **Add > Add project from disk** and select:
   ```text
   /Users/gimseoncheol/Desktop/chess_game/unity/ChessBoard
   ```
3. In the Unity Project window, open the main scene:
   ```text
   Assets/Scenes/ChessBoard.unity
   ```

### Step 2: Run in Play Mode or Preview in Edit Mode
- **Play Mode**: Press the **Play** button in the Unity Editor toolbar. `BoardRenderer.Awake()` automatically generates the 8×8 chessboard (`Square_a1` .. `Square_h8`) and spawns all 32 initial pieces from the standard starting FEN (`rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`).
- **Edit Mode Scene Preview**: In the top menu bar, select **Tools > Still Chess > Rebuild 3D Chess Scene** (`ChessSceneSetupEditor.cs`) to materialize all 64 squares and 32 pieces directly in the Scene view hierarchy without entering Play Mode.

### Step 3: Run Unity EditMode Tests
1. In the Unity Editor, open **Window > General > Test Runner**.
2. Select the **EditMode** tab and click **Run All**.
3. `BoardRendererEditModeTests` verifies:
   - `a1` through `h8` coordinate mapping and square color alternation (`a1` is dark, `b1` is light).
   - 64 board squares generated with alternating shared materials.
   - 32 initial pieces (16 White, 16 Black) across all 6 piece types (`P`, `N`, `B`, `R`, `Q`, `K`).
   - Reconstructing arbitrary mid-game FEN positions via `BoardRenderer.TryApplyFenSnapshot` and rejecting malformed FEN strings without mutating the active board.

### Step 4: Run on an Android Device
1. Open **File > Build Profiles** (or **File > Build Settings**).
2. Select **Android** and click **Switch Platform**.
3. Ensure `Assets/Scenes/ChessBoard.unity` is checked in the **Scene List**.
4. Connect an ARM64 Android device with USB debugging enabled, then click **Build and Run**.

