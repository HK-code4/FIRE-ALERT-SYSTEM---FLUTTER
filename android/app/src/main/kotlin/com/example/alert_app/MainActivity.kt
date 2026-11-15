package com.example.alert_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.alert_app/alert"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "checkFireAlert") {
                    val hasAlert = intent?.getBooleanExtra("fire_alert", false) ?: false
                    result.success(hasAlert)
                } else {
                    result.notImplemented()
                }
            }
    }
}