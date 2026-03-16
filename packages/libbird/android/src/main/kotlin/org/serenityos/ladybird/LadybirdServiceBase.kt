package org.serenityos.ladybird

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.ParcelFileDescriptor
import android.util.Log
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

const val MSG_SET_RESOURCE_ROOT = 1
const val MSG_TRANSFER_SOCKET = 2

abstract class LadybirdServiceBase(protected val tagName: String) : Service() {
  private val threadPool = Executors.newCachedThreadPool()
  protected lateinit var resourceDir: String

  override fun onCreate() {
    super.onCreate()
    Log.i(tagName, "Creating service")
  }

  override fun onDestroy() {
    super.onDestroy()
    Log.i(tagName, "Destroying service")
  }

  override fun onBind(intent: Intent?): IBinder {
    return Messenger(IncomingHandler(WeakReference(this))).binder
  }

  private fun handleTransferSockets(msg: Message) {
    val ipcSocket = msg.data.getParcelable<ParcelFileDescriptor>("IPC_SOCKET") ?: return
    threadPool.execute {
      nativeThreadLoop(ipcSocket.detachFd())
    }
  }

  private fun handleSetResourceRoot(msg: Message) {
    resourceDir = msg.data.getString("PATH") ?: return
    initNativeCode(resourceDir, tagName)
  }

  private external fun nativeThreadLoop(ipcSocket: Int)
  private external fun initNativeCode(resourceDir: String, tagName: String)

  abstract fun handleServiceSpecificMessage(msg: Message): Boolean

  class IncomingHandler(private val serviceRef: WeakReference<LadybirdServiceBase>) : Handler(Looper.getMainLooper()) {
    override fun handleMessage(msg: Message) {
      val service = serviceRef.get() ?: return
      when (msg.what) {
        MSG_TRANSFER_SOCKET -> service.handleTransferSockets(msg)
        MSG_SET_RESOURCE_ROOT -> service.handleSetResourceRoot(msg)
        else -> if (!service.handleServiceSpecificMessage(msg)) super.handleMessage(msg)
      }
    }
  }
}
