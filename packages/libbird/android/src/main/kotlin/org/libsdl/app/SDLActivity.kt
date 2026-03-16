package org.libsdl.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.view.Surface

/**
 * Minimal SDL activity shim required by SDL JNI initialization.
 * Ladybird's Android service process does not launch this activity,
 * but SDL's native library expects the class to exist at load time.
 */
open class SDLActivity : Activity() {
	companion object {
		@JvmStatic external fun nativeGetVersion(): String
		@JvmStatic external fun nativeSetupJNI(): Int
		@JvmStatic external fun nativeInitMainThread()
		@JvmStatic external fun nativeCleanupMainThread()
		@JvmStatic external fun nativeRunMain(library: String, function: String, arguments: Any?): Int
		@JvmStatic external fun onNativeDropFile(filename: String)
		@JvmStatic external fun nativeSetScreenResolution(width: Int, height: Int, deviceWidth: Int, deviceHeight: Int, density: Float, rate: Float)
		@JvmStatic external fun onNativeResize()
		@JvmStatic external fun onNativeSurfaceCreated()
		@JvmStatic external fun onNativeSurfaceChanged()
		@JvmStatic external fun onNativeSurfaceDestroyed()
		@JvmStatic external fun onNativeKeyDown(keycode: Int)
		@JvmStatic external fun onNativeKeyUp(keycode: Int)
		@JvmStatic external fun onNativeSoftReturnKey(): Boolean
		@JvmStatic external fun onNativeKeyboardFocusLost()
		@JvmStatic external fun onNativeTouch(touchDeviceId: Int, pointerFingerId: Int, action: Int, x: Float, y: Float, p: Float)
		@JvmStatic external fun onNativeMouse(button: Int, action: Int, x: Float, y: Float, relative: Boolean)
		@JvmStatic external fun onNativePen(pointerId: Int, button: Int, action: Int, x: Float, y: Float, p: Float)
		@JvmStatic external fun onNativeAccel(x: Float, y: Float, z: Float)
		@JvmStatic external fun onNativeClipboardChanged()
		@JvmStatic external fun nativeLowMemory()
		@JvmStatic external fun onNativeLocaleChanged()
		@JvmStatic external fun onNativeDarkModeChanged(enabled: Boolean)
		@JvmStatic external fun nativeSendQuit()
		@JvmStatic external fun nativeQuit()
		@JvmStatic external fun nativePause()
		@JvmStatic external fun nativeResume()
		@JvmStatic external fun nativeFocusChanged(hasFocus: Boolean)
		@JvmStatic external fun nativeGetHint(name: String): String?
		@JvmStatic external fun nativeGetHintBoolean(name: String, defaultValue: Boolean): Boolean
		@JvmStatic external fun nativeSetenv(name: String, value: String)
		@JvmStatic external fun nativeSetNaturalOrientation(naturalOrientation: Int)
		@JvmStatic external fun onNativeRotationChanged(rotation: Int)
		@JvmStatic external fun onNativeInsetsChanged(left: Int, right: Int, top: Int, bottom: Int)
		@JvmStatic external fun nativeAddTouch(touchId: Int, name: String)
		@JvmStatic external fun nativePermissionResult(requestCode: Int, result: Boolean)
		@JvmStatic external fun nativeAllowRecreateActivity(): Boolean
		@JvmStatic external fun nativeCheckSDLThreadCounter(): Int
		@JvmStatic external fun onNativeFileDialog(requestCode: Int, fileList: Array<String>?, filter: Int)

		@JvmStatic fun clipboardGetText(): String = ""
		@JvmStatic fun clipboardHasText(): Boolean = false
		@JvmStatic fun clipboardSetText(text: String) {}
		@JvmStatic fun createCustomCursor(colors: IntArray, width: Int, height: Int, hotSpotX: Int, hotSpotY: Int): Int = 0
		@JvmStatic fun destroyCustomCursor(cursorId: Int) {}
		@JvmStatic fun getContext(): Context? = currentApplicationContext()
		@JvmStatic fun getManifestEnvironmentVariables(): Boolean = false
		@JvmStatic fun getNativeSurface(): Surface? = null
		@JvmStatic fun initTouch() {}
		@JvmStatic fun isAndroidTV(): Boolean = false
		@JvmStatic fun isChromebook(): Boolean = false
		@JvmStatic fun isDeXMode(): Boolean = false
		@JvmStatic fun isScreenKeyboardShown(): Boolean = false
		@JvmStatic fun isTablet(): Boolean = false
		@JvmStatic fun manualBackButton() {}
		@JvmStatic fun minimizeWindow() {}
		@JvmStatic fun openURL(url: String): Boolean = false
		@JvmStatic fun requestPermission(permission: String, requestCode: Int) {}
		@JvmStatic fun showToast(message: String, gravity: Int, xOffset: Int, yOffset: Int, length: Int): Boolean = false
		@JvmStatic fun sendMessage(command: Int, param: Int): Boolean = false
		@JvmStatic fun setActivityTitle(title: String): Boolean = false
		@JvmStatic fun setCustomCursor(cursorId: Int): Boolean = false
		@JvmStatic fun setOrientation(width: Int, height: Int, resizable: Boolean, hint: String?) {}
		@JvmStatic fun setRelativeMouseEnabled(enabled: Boolean): Boolean = false
		@JvmStatic fun setSystemCursor(cursorId: Int): Boolean = false
		@JvmStatic fun setWindowStyle(fullscreen: Boolean) {}
		@JvmStatic fun shouldMinimizeOnFocusLoss(): Boolean = false
		@JvmStatic fun showTextInput(x: Int, y: Int, width: Int, height: Int, inputType: Int): Boolean = false
		@JvmStatic fun supportsRelativeMouse(): Boolean = false
		@JvmStatic fun openFileDescriptor(uri: String, mode: String): Int = -1
		@JvmStatic fun showFileDialog(filters: Array<String>, allowMany: Boolean, isSave: Boolean, requestCode: Int): Boolean = false
		@JvmStatic fun getPreferredLocales(): String = ""

		private fun currentApplicationContext(): Context? {
			return try {
				val activityThread = Class.forName("android.app.ActivityThread")
				val method = activityThread.getMethod("currentApplication")
				method.invoke(null) as? Application
			} catch (_: Throwable) {
				null
			}
		}
	}
}
