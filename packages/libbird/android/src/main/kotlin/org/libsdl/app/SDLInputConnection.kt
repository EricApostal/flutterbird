package org.libsdl.app

class SDLInputConnection {
    companion object {
        @JvmStatic external fun nativeCommitText(text: String, newCursorPosition: Int)
        @JvmStatic external fun nativeGenerateScancodeForUnichar(chUnicode: Char)
    }
}
