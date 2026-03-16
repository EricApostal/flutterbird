package org.libsdl.app

class SDLControllerManager {
    companion object {
        @JvmStatic external fun nativeSetupJNI(): Int
        @JvmStatic external fun onNativePadDown(deviceId: Int, keycode: Int): Boolean
        @JvmStatic external fun onNativePadUp(deviceId: Int, keycode: Int): Boolean
        @JvmStatic external fun onNativeJoy(deviceId: Int, axis: Int, value: Float)
        @JvmStatic external fun onNativeHat(deviceId: Int, hatId: Int, x: Int, y: Int)
        @JvmStatic external fun nativeAddJoystick(
            deviceId: Int,
            deviceName: String,
            deviceDesc: String,
            vendorId: Int,
            productId: Int,
            buttonMask: Int,
            numAxes: Int,
            axisMask: Int,
            numHats: Int,
            canRumble: Boolean,
        )
        @JvmStatic external fun nativeRemoveJoystick(deviceId: Int)
        @JvmStatic external fun nativeAddHaptic(deviceId: Int, deviceName: String)
        @JvmStatic external fun nativeRemoveHaptic(deviceId: Int)

        @JvmStatic fun pollInputDevices() {}
        @JvmStatic fun pollHapticDevices() {}
        @JvmStatic fun hapticRun(deviceId: Int, intensity: Float, length: Int) {}
        @JvmStatic fun hapticRumble(deviceId: Int, lowFrequencyIntensity: Float, highFrequencyIntensity: Float, length: Int) {}
        @JvmStatic fun hapticStop(deviceId: Int) {}
    }
}
