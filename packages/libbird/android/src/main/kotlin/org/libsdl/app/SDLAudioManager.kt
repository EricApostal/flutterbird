package org.libsdl.app

class SDLAudioManager {
    companion object {
        @JvmStatic external fun nativeSetupJNI(): Int
        @JvmStatic external fun addAudioDevice(recording: Boolean, name: String, deviceId: Int)
        @JvmStatic external fun removeAudioDevice(recording: Boolean, deviceId: Int)

        @JvmStatic fun registerAudioDeviceCallback() {}
        @JvmStatic fun unregisterAudioDeviceCallback() {}
        @JvmStatic fun audioSetThreadPriority(recording: Boolean, deviceId: Int) {}
    }
}
