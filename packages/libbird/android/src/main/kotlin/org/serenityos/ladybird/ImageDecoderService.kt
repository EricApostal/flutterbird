package org.serenityos.ladybird

import android.os.Message

class ImageDecoderService : LadybirdServiceBase("ImageDecoderService") {
  override fun handleServiceSpecificMessage(msg: Message): Boolean = false

  companion object {
    init {
      System.loadLibrary("imagedecoderservice")
    }
  }
}
