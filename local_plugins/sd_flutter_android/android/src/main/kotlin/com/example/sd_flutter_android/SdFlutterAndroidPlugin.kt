package com.example.sd_flutter_android

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*

class SdFlutterAndroidPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

  // Callback object passed to JNI; JNI calls onProgress(step, total) from worker threads
  inner class ProgressCallback {
    fun onProgress(step: Int, total: Int) {
      // Marshal back to main thread for MethodChannel
      CoroutineScope(Dispatchers.Main).launch {
        channel.invokeMethod("onProgress", mapOf("step" to step, "total" to total))
      }
    }
  }

  // Native methods (linked to sd_jni_wrapper.cpp)
  private external fun initModel(path: String, controlNetPath: String): Boolean
  private external fun getLastError(): String?
  private external fun generateImage(
    prompt: String,
    steps: Int,
    callback: ProgressCallback,
    referenceImage: ByteArray?,
    referenceWidth: Int,
    referenceHeight: Int,
    strength: Float,
    controlImage: ByteArray?,
    controlWidth: Int,
    controlHeight: Int,
    controlStrength: Float,
  ): ByteArray?
  private external fun unloadModel()

  init {
    System.loadLibrary("sd_jni")
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "sd_flutter_android")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "initModel" -> {
        val path = call.argument<String>("path")
        val controlNetPath = call.argument<String>("controlNetPath") ?: ""
        if (path != null) {
          scope.launch {
            try {
              val success = initModel(path, controlNetPath)
              // On failure surface the last sd.cpp log line as the result
              // string so Dart can show it in the UI instead of a generic
              // "Model initialization failed" message.
              val reply: Any = if (success) true else (getLastError() ?: false)
              withContext(Dispatchers.Main) { result.success(reply) }
            } catch (e: Exception) {
              withContext(Dispatchers.Main) { result.error("INIT_FAILED", e.message, null) }
            }
          }
        } else {
          result.error("INVALID_ARGUMENT", "Path is null", null)
        }
      }
      "generateImage" -> {
        val prompt = call.argument<String>("prompt")
        val steps = call.argument<Int>("steps") ?: 20
        val referenceImage = call.argument<ByteArray>("referenceImage")
        val referenceWidth = call.argument<Int>("referenceWidth") ?: 0
        val referenceHeight = call.argument<Int>("referenceHeight") ?: 0
        val strength = (call.argument<Double>("strength") ?: 0.75).toFloat()
        val controlImage = call.argument<ByteArray>("controlImage")
        val controlWidth = call.argument<Int>("controlWidth") ?: 0
        val controlHeight = call.argument<Int>("controlHeight") ?: 0
        val controlStrength = (call.argument<Double>("controlStrength") ?: 1.0).toFloat()
        if (prompt != null) {
          scope.launch {
            try {
              val callback = ProgressCallback()
              val bytes = generateImage(
                prompt,
                steps,
                callback,
                referenceImage,
                referenceWidth,
                referenceHeight,
                strength,
                controlImage,
                controlWidth,
                controlHeight,
                controlStrength,
              )
              withContext(Dispatchers.Main) {
                if (bytes != null) {
                  result.success(bytes)
                } else {
                  result.error("GENERATION_FAILED", "Image generation returned null", null)
                }
              }
            } catch (e: Exception) {
              withContext(Dispatchers.Main) {
                result.error("GENERATION_FAILED", e.message, null)
              }
            }
          }
        } else {
          result.error("INVALID_ARGUMENT", "Prompt is null", null)
        }
      }
      "unloadModel" -> {
        scope.launch {
          try {
            unloadModel()
            withContext(Dispatchers.Main) { result.success(null) }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) { result.error("UNLOAD_FAILED", e.message, null) }
          }
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    scope.cancel()
  }
}
