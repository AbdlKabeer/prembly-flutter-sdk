package com.prembly.prembly_identity_kyc

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

/**
 * The native side only reads the device. Every method answers with JSON text, which keeps the
 * channel contract small and identical on Android and iOS. It never asks for a permission.
 */
class PremblyIdentityKycPlugin : FlutterPlugin, MethodCallHandler {
  private var channel: MethodChannel? = null
  private var context: Context? = null
  private var collector: SignalCollector? = null

  // The checks touch the file system and system services, so keep them off the main thread.
  private val worker = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    collector = SignalCollector(binding.applicationContext)
    channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
    collector = null
    context = null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    val collector = collector
    val context = context
    if (collector == null || context == null) {
      result.error("not_attached", "The plugin is not attached to an engine.", null)
      return
    }
    when (call.method) {
      "getAppInfo" -> respond(result) { collector.appInfo().toString() }
      "getDeviceId" -> respond(result) { DeviceIdStore.deviceId(context) }
      "collectSignals" -> {
        val includeLocation = call.argument<Boolean>("includeLocation") ?: false
        respond(result) { collector.collect(includeLocation).toString() }
      }
      "checkScreenCapture" -> respond(result) { collector.screenCapture().toString() }
      else -> result.notImplemented()
    }
  }

  private fun respond(result: Result, work: () -> String) {
    worker.execute {
      try {
        val value = work()
        main.post { result.success(value) }
      } catch (error: Throwable) {
        main.post { result.error("native_failed", error.message, null) }
      }
    }
  }

  companion object {
    const val CHANNEL = "com.prembly.identity_kyc/device"
  }
}
