package dev.chessboard.chess_game

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "chess/storage/v1",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageDirectory" -> result.success(applicationContext.filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
    }
}
