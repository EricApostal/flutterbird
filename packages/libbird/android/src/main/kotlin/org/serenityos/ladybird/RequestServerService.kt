package org.serenityos.ladybird

import android.os.Message

class RequestServerService : LadybirdServiceBase("RequestServerService") {
  override fun handleServiceSpecificMessage(msg: Message): Boolean = false

  companion object {
    init {
      System.loadLibrary("requestserverservice")
    }
  }
}
