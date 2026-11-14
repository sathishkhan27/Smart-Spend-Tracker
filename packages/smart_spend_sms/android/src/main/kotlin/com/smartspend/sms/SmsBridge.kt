package com.smartspend.sms

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Telephony
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/**
 * Native bridge for reading the SMS inbox (READ_SMS) and listening for new
 * messages (RECEIVE_SMS). Only invoked after the user has granted consent and
 * the runtime permission. Message bodies are handed to Dart for on-device
 * parsing; nothing is uploaded from here.
 */
object SmsBridge {
    private const val METHOD_CHANNEL = "smart_spend/sms"
    private const val EVENT_CHANNEL = "smart_spend/sms_events"
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(true)
                "hasPermission" -> result.success(hasPermission(context))
                "count" -> {
                    if (!hasPermission(context)) return@setMethodCallHandler result.error("PERMISSION", "READ_SMS not granted", null)
                    val since = (call.argument<Number>("sinceMillis") ?: 0).toLong()
                    executor.execute {
                        try { val v = count(context, since); main.post { result.success(v) } } catch (e: Exception) { main.post { result.error("QUERY", e.message, null) } }
                    }
                }
                "query" -> {
                    if (!hasPermission(context)) return@setMethodCallHandler result.error("PERMISSION", "READ_SMS not granted", null)
                    val since = (call.argument<Number>("sinceMillis") ?: 0).toLong()
                    val afterId = (call.argument<Number>("afterId") ?: 0).toLong()
                    val limit = call.argument<Int>("limit") ?: 200
                    executor.execute {
                        try { val v = query(context, since, afterId, limit); main.post { result.success(v) } } catch (e: Exception) { main.post { result.error("QUERY", e.message, null) } }
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            private var receiver: BroadcastReceiver? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED) {
                    events.error("PERMISSION", "RECEIVE_SMS not granted", null)
                    return
                }
                receiver = object : BroadcastReceiver() {
                    override fun onReceive(ctx: Context, intent: Intent) {
                        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
                        if (parts.isEmpty()) return
                        val body = parts.joinToString("") { it.messageBody ?: "" }
                        events.success(mapOf(
                            "id" to "live-${parts[0].timestampMillis}-${parts[0].originatingAddress}",
                            "address" to (parts[0].originatingAddress ?: ""),
                            "body" to body,
                            "date" to parts[0].timestampMillis,
                        ))
                    }
                }
                val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
                if (Build.VERSION.SDK_INT >= 33) {
                    context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    context.registerReceiver(receiver, filter)
                }
            }

            override fun onCancel(arguments: Any?) {
                receiver?.let { runCatching { context.unregisterReceiver(it) } }
                receiver = null
            }
        })
    }

    private fun hasPermission(context: Context) =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    private val inbox: Uri = Uri.parse("content://sms/inbox")

    private fun count(context: Context, since: Long): Int {
        context.contentResolver.query(inbox, arrayOf("_id"), "date > ?", arrayOf(since.toString()), null)?.use {
            return it.count
        }
        return 0
    }

    private fun query(context: Context, since: Long, afterId: Long, limit: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val selection = "date > ? AND _id > ?"
        val args = arrayOf(since.toString(), afterId.toString())
        context.contentResolver.query(inbox, arrayOf("_id", "address", "body", "date"), selection, args, "_id ASC")?.use { c ->
            val idI = c.getColumnIndexOrThrow("_id")
            val addrI = c.getColumnIndexOrThrow("address")
            val bodyI = c.getColumnIndexOrThrow("body")
            val dateI = c.getColumnIndexOrThrow("date")
            while (c.moveToNext() && out.size < limit) {
                out.add(mapOf(
                    "id" to c.getLong(idI).toString(),
                    "address" to (c.getString(addrI) ?: ""),
                    "body" to (c.getString(bodyI) ?: ""),
                    "date" to c.getLong(dateI),
                ))
            }
        }
        return out
    }
}

