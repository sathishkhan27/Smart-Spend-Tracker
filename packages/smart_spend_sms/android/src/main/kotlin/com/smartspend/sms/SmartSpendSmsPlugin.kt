package com.smartspend.sms

import io.flutter.embedding.engine.plugins.FlutterPlugin


/**
 * Plugin entry point: Flutter attaches this to every engine (the app UI and
 * the WorkManager background-sync engine), so SMS can be read in both.
 */
class SmartSpendSmsPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        SmsBridge.register(binding.applicationContext, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
