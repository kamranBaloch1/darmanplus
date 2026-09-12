package com.user.darman

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.user.darman/incoming_call"
        private const val PREFS = "darman_incoming_call"
        private const val PENDING_ACCEPTED_INVITE = "pending_accepted_invite"
        private const val CALL_DATA = "EXTRA_CALLKIT_CALL_DATA"
        private const val CALL_ID = "EXTRA_CALLKIT_ID"
        private const val ACCEPT_ACTION_SUFFIX =
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
    }

    private var incomingCallChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Persist the CallKit launch before Flutter starts. The plugin event can
        // otherwise fire while the Dart engine is still booting and be lost.
        captureAcceptedCall(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        captureAcceptedCall(intent)
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingCallChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
        incomingCallChannel?.setMethodCallHandler { call, result ->
            val preferences = getSharedPreferences(PREFS, MODE_PRIVATE)
            when (call.method) {
                "takePendingAcceptedCall" -> {
                    val inviteId = preferences
                        .getString(PENDING_ACCEPTED_INVITE, null)
                        ?.trim()
                        .orEmpty()
                    if (inviteId.isEmpty()) {
                        result.success(null)
                    } else {
                        preferences.edit().remove(PENDING_ACCEPTED_INVITE).commit()
                        result.success(mapOf("invite_id" to inviteId))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun captureAcceptedCall(sourceIntent: Intent?) {
        val action = sourceIntent?.action.orEmpty()
        if (!action.endsWith(ACCEPT_ACTION_SUFFIX)) return
        val callData = sourceIntent?.getBundleExtra(CALL_DATA)
        val inviteId = callData?.getString(CALL_ID)?.trim().orEmpty()
        if (inviteId.isEmpty()) return
        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putString(PENDING_ACCEPTED_INVITE, inviteId)
            .commit()
        incomingCallChannel?.invokeMethod(
            "acceptedCall",
            mapOf("invite_id" to inviteId),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    getSharedPreferences(PREFS, MODE_PRIVATE)
                        .edit()
                        .remove(PENDING_ACCEPTED_INVITE)
                        .commit()
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) = Unit

                override fun notImplemented() = Unit
            },
        )
    }
}
