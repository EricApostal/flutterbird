package org.serenityos.ladybird

import android.content.Context
import android.content.Intent
import android.os.Message
import android.util.Log

class WebContentService : LadybirdServiceBase("WebContentService") {
  override fun handleServiceSpecificMessage(msg: Message): Boolean = false

  init {
    nativeInit()
  }

  private fun bindRequestServer(ipcFd: Int) {
    val connector = LadybirdServiceConnection(ipcFd, resourceDir)
    connector.onDisconnect = { Log.e("WebContentService", "RequestServer died") }
    bindService(Intent(this, RequestServerService::class.java), connector, Context.BIND_AUTO_CREATE)
  }

  private fun bindImageDecoder(ipcFd: Int) {
    val connector = LadybirdServiceConnection(ipcFd, resourceDir)
    connector.onDisconnect = { Log.e("WebContentService", "ImageDecoder died") }
    bindService(Intent(this, ImageDecoderService::class.java), connector, Context.BIND_AUTO_CREATE)
  }

  external fun nativeInit()

  companion object {
    init {
      System.loadLibrary("webcontentservice")
    }
  }
}
