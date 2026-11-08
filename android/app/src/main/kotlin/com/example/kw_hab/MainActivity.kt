package com.example.kw_hab

import android.Manifest
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Android side of the `kw_hab/shell` channel (lib/shell/native_shell.dart).
 * macOS's version is macos/Runner/MainFlutterWindow.swift.
 *
 * Dart -> native: `requestPermissions` with a list of "camera"/"microphone",
 * answered with the ones the user allowed. The web view can only use the
 * camera or microphone once the app itself has the Android permission.
 * `setTitle` is not implemented: a phone app has no window title.
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingNames: List<String> = emptyList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kw_hab/shell")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermissions" -> {
                        val names = (call.arguments as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                        requestAndroidPermissions(names, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun androidPermission(name: String): String? = when (name) {
        "camera" -> Manifest.permission.CAMERA
        "microphone" -> Manifest.permission.RECORD_AUDIO
        else -> null
    }

    private fun isGranted(permission: String) =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun requestAndroidPermissions(names: List<String>, result: MethodChannel.Result) {
        val known = names.filter { androidPermission(it) != null }
        val missing = known.mapNotNull { androidPermission(it) }.filter { !isGranted(it) }
        if (missing.isEmpty()) {
            result.success(known)
            return
        }
        // One request at a time; a second one answers with what's granted now.
        if (pendingResult != null) {
            result.success(known.filter { isGranted(androidPermission(it)!!) })
            return
        }
        pendingResult = result
        pendingNames = known
        requestPermissions(missing.toTypedArray(), PERMISSIONS_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSIONS_REQUEST) return
        val result = pendingResult ?: return
        pendingResult = null
        result.success(pendingNames.filter { isGranted(androidPermission(it)!!) })
    }

    companion object {
        private const val PERMISSIONS_REQUEST = 4201
    }
}
