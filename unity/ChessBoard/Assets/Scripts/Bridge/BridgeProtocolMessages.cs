using System;
using System.Text;

namespace StillChess.Board.Bridge
{
    [Serializable]
    public sealed class BridgeCameraDto
    {
        public string orientation;
        public string preset;
    }

    [Serializable]
    public sealed class BridgeHighlightMoveDto
    {
        public string to;
        public string style;
        public string[] promotionChoices;
    }

    [Serializable]
    public sealed class BridgeHighlightsDto
    {
        public string selectionRequestId;
        public string selectedSquare;
        public BridgeHighlightMoveDto[] moves;
        public bool inputEnabled;
    }

    [Serializable]
    public sealed class BridgeStatusDto
    {
        public string phase;
        public string sideToMove;
        public string checkSquare;
        public string result;
        public string termination;
        public bool canClaimDraw;
    }

    [Serializable]
    public sealed class BridgeIncomingPayloadDto
    {
        public string rendererInstanceId;
        public string fen;
        public string selectedSquare;
        public BridgeHighlightsDto highlights;
        public BridgeHighlightMoveDto[] moves;
        public BridgeStatusDto status;
        public BridgeCameraDto camera;
        public string orientation;
        public string preset;
        public int durationMs;
        public bool inputEnabled;
    }

    [Serializable]
    public sealed class BridgeIncomingEnvelopeDto
    {
        public int protocolVersion;
        public string type;
        public string messageId;
        public string sessionId;
        public string gameId;
        public int revision;
        public int sequence;
        public string replyTo;
        public BridgeIncomingPayloadDto payload;
    }

    /// <summary>
    /// Formats and validates JSON protocol messages conforming to version 1 of
    /// <c>docs/unity_flutter_bridge.md</c>.
    /// </summary>
    public static class BridgeProtocolMessages
    {
        public const int SupportedProtocolVersion = 1;
        public const string TypeUnityReady = "unity.ready";
        public const string TypeBoardSnapshot = "board.snapshot";
        public const string TypeSquareSelected = "player.squareSelected";
        public const string TypeLegalMovesHighlight = "legalMoves.highlight";
        public const string TypeGameStatus = "game.status";
        public const string TypeCameraReset = "camera.reset";
        public const string TypeBridgeAck = "bridge.ack";

        /// <summary>
        /// Builds a normative <c>player.squareSelected</c> UTF-8 JSON object for Flutter.
        /// Explicitly serializes nullable strings (<c>replyTo</c>, <c>selectionRequestId</c>) as JSON <c>null</c>
        /// when absent, matching <c>docs/unity_flutter_bridge.md</c>.
        /// </summary>
        public static string BuildSquareSelectedJson(
            string messageId,
            string sessionId,
            string gameId,
            int revision,
            int sequence,
            string square,
            string interaction = "tap",
            string selectionRequestId = null,
            string replyTo = null)
        {
            var sb = new StringBuilder(256);
            sb.Append('{');
            sb.Append("\"protocolVersion\":").Append(SupportedProtocolVersion).Append(',');
            sb.Append("\"type\":\"").Append(TypeSquareSelected).Append("\",");
            sb.Append("\"messageId\":").Append(FormatJsonStringOrNull(messageId)).Append(',');
            sb.Append("\"sessionId\":").Append(FormatJsonStringOrNull(sessionId)).Append(',');
            sb.Append("\"gameId\":").Append(FormatJsonStringOrNull(gameId)).Append(',');
            sb.Append("\"revision\":").Append(revision).Append(',');
            sb.Append("\"sequence\":").Append(sequence).Append(',');
            sb.Append("\"replyTo\":").Append(FormatJsonStringOrNull(replyTo)).Append(',');
            sb.Append("\"payload\":{");
            sb.Append("\"square\":").Append(FormatJsonStringOrNull(square)).Append(',');
            sb.Append("\"interaction\":").Append(FormatJsonStringOrNull(interaction)).Append(',');
            sb.Append("\"selectionRequestId\":").Append(FormatJsonStringOrNull(selectionRequestId));
            sb.Append("}}");
            return sb.ToString();
        }

        public static string FormatJsonStringOrNull(string value)
        {
            if (string.IsNullOrEmpty(value))
            {
                return "null";
            }

            var sb = new StringBuilder(value.Length + 4);
            sb.Append('"');
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                switch (c)
                {
                    case '"':
                        sb.Append("\\\"");
                        break;
                    case '\\':
                        sb.Append("\\\\");
                        break;
                    case '\n':
                        sb.Append("\\n");
                        break;
                    case '\r':
                        sb.Append("\\r");
                        break;
                    case '\t':
                        sb.Append("\\t");
                        break;
                    default:
                        sb.Append(c);
                        break;
                }
            }

            sb.Append('"');
            return sb.ToString();
        }
    }
}

