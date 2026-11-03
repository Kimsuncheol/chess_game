using System.Collections.Generic;
using UnityEngine;

namespace StillChess.Board.Bridge
{
    /// <summary>
    /// Transport abstraction for sending versioned JSON messages from Unity to the Flutter host.
    /// Keeps the Unity scene decoupled from any specific Flutter–Unity embedding plugin.
    /// </summary>
    public interface IFlutterBridgeTransport
    {
        void SendToFlutter(string jsonMessage);
    }

    /// <summary>
    /// Default transport that records messages in memory and optionally dispatches to the Android host
    /// when running on an Android device.
    /// </summary>
    public sealed class DefaultFlutterBridgeTransport : IFlutterBridgeTransport
    {
        private readonly List<string> _sentMessages = new List<string>();

        public IReadOnlyList<string> SentMessages => _sentMessages;

        public string LastSentMessage => _sentMessages.Count > 0 ? _sentMessages[_sentMessages.Count - 1] : null;

        public void ClearSentMessages() => _sentMessages.Clear();

        public void SendToFlutter(string jsonMessage)
        {
            if (string.IsNullOrEmpty(jsonMessage))
            {
                return;
            }

            _sentMessages.Add(jsonMessage);

#if UNITY_ANDROID && !UNITY_EDITOR
            try
            {
                using var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer");
                using var currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity");
                currentActivity?.Call("onUnityBridgeMessage", jsonMessage);
            }
            catch (System.Exception)
            {
                // Host activity may not register onUnityBridgeMessage in standalone test builds.
            }
#endif
        }
    }
}

