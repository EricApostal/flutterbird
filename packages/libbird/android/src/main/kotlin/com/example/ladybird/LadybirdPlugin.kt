package com.example.ladybird

import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.PorterDuff
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import org.serenityos.ladybird.LadybirdServiceConnection
import org.serenityos.ladybird.WebContentService

class LadybirdPlugin : FlutterPlugin, MethodCallHandler, Choreographer.FrameCallback {
  private lateinit var channel: MethodChannel
  private var binding: FlutterPluginBinding? = null
  private var textureRegistry: TextureRegistry? = null
  private val textures = mutableMapOf<Long, TextureState>()
  private val serviceConnections = mutableListOf<ServiceConnection>()
  private var attached = false

  private data class TextureState(
    val viewId: Int,
    val entry: TextureRegistry.SurfaceTextureEntry,
    val surface: Surface,
    var bitmap: Bitmap? = null,
  )

  override fun onAttachedToEngine(binding: FlutterPluginBinding) {
    this.binding = binding
    System.loadLibrary("ladybird_jni")
    nativeInitLadybird()

    textureRegistry = binding.textureRegistry
    channel = MethodChannel(binding.binaryMessenger, "ladybird")
    channel.setMethodCallHandler(this)
    attached = true
    Choreographer.getInstance().postFrameCallback(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
    attached = false
    Choreographer.getInstance().removeFrameCallback(this)
    val appContext = this.binding?.applicationContext
    if (appContext != null) {
      for (connection in serviceConnections) {
        runCatching { appContext.unbindService(connection) }
      }
    }
    serviceConnections.clear()
    releaseAllTextures()
    channel.setMethodCallHandler(null)
    textureRegistry = null
    this.binding = null
  }

  fun bindWebContentServiceFromNative(ipcFd: Int) {
    val pluginBinding = binding ?: return
    val appContext = pluginBinding.applicationContext
    val resourceDir = appContext.dataDir.absolutePath

    val connector = LadybirdServiceConnection(ipcFd, resourceDir)
    connector.onDisconnect = {
      Log.e("LadybirdPlugin", "WebContent service disconnected")
    }

    val bound = appContext.bindService(
      Intent(appContext, WebContentService::class.java),
      connector,
      Context.BIND_AUTO_CREATE,
    )

    if (bound) {
      serviceConnections.add(connector)
    } else {
      Log.e("LadybirdPlugin", "Failed to bind WebContentService")
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "createTexture" -> {
        val viewId = (call.arguments as? Number)?.toInt()
        if (viewId == null) {
          result.error("INVALID_ARGS", "Expected int viewId", null)
          return
        }

        val registry = textureRegistry
        if (registry == null) {
          result.error("UNAVAILABLE", "Texture registry is null", null)
          return
        }

        val entry = registry.createSurfaceTexture()
        val surface = Surface(entry.surfaceTexture())
        val textureId = entry.id()

        textures[textureId]?.let { existing ->
          existing.surface.release()
          existing.entry.release()
        }

        textures[textureId] = TextureState(
          viewId = viewId,
          entry = entry,
          surface = surface,
        )

        result.success(textureId)
      }

      "unregisterTexture" -> {
        val textureId = (call.arguments as? Number)?.toLong()
        if (textureId == null) {
          result.error("INVALID_ARGS", "Expected int textureId", null)
          return
        }

        releaseTexture(textureId)
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }

  override fun doFrame(frameTimeNanos: Long) {
    if (!attached) {
      return
    }

    if (textures.isNotEmpty()) {
      nativeTickLadybird()
    }

    // Draw all active views to their bound surfaces once per frame.
    for (state in textures.values) {
      renderTexture(state)
    }

    Choreographer.getInstance().postFrameCallback(this)
  }

  private fun renderTexture(state: TextureState) {
    val width = nativeGetTextureWidth(state.viewId)
    val height = nativeGetTextureHeight(state.viewId)
    if (width <= 0 || height <= 0) {
      return
    }

    val byteBuffer = nativeGetLatestPixelBuffer(state.viewId)
    if (byteBuffer == null || byteBuffer.capacity() < width * height * 4) {
      return
    }

    state.entry.surfaceTexture().setDefaultBufferSize(width, height)

    var bitmap = state.bitmap
    if (bitmap == null || bitmap.width != width || bitmap.height != height || bitmap.isRecycled) {
      bitmap?.recycle()
      bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
      state.bitmap = bitmap
    }

    byteBuffer.rewind()
    bitmap.copyPixelsFromBuffer(byteBuffer)

    var canvas: Canvas? = null
    try {
      canvas = state.surface.lockCanvas(null)
      canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.SRC)
      canvas.drawBitmap(bitmap, 0f, 0f, null)
    } catch (_: Throwable) {
      // Ignore frame draw failures and retry on next frame.
    } finally {
      if (canvas != null) {
        state.surface.unlockCanvasAndPost(canvas)
      }
    }
  }

  private fun releaseTexture(textureId: Long) {
    val state = textures.remove(textureId) ?: return
    state.bitmap?.recycle()
    state.surface.release()
    state.entry.release()
  }

  private fun releaseAllTextures() {
    val ids = textures.keys.toList()
    for (id in ids) {
      releaseTexture(id)
    }
  }

  private external fun nativeTickLadybird()

  private external fun nativeInitLadybird()

  private external fun nativeGetLatestPixelBuffer(viewId: Int): ByteBuffer?

  private external fun nativeGetTextureWidth(viewId: Int): Int

  private external fun nativeGetTextureHeight(viewId: Int): Int
}
