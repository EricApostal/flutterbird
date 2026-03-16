package org.libsdl.app

class HIDDeviceManager {
    external fun HIDDeviceRegisterCallback()
    external fun HIDDeviceReleaseCallback()
    external fun HIDDeviceConnected(
        deviceId: Int,
        identifier: String,
        vendorId: Int,
        productId: Int,
        serialNumber: String,
        releaseNumber: Int,
        manufacturer: String,
        product: String,
        interfaceNumber: Int,
        interfaceClass: Int,
        interfaceSubclass: Int,
        interfaceProtocol: Int,
        bluetooth: Boolean,
    )

    external fun HIDDeviceOpenPending(deviceId: Int)
    external fun HIDDeviceOpenResult(deviceId: Int, opened: Boolean)
    external fun HIDDeviceDisconnected(deviceId: Int)
    external fun HIDDeviceInputReport(deviceId: Int, value: ByteArray)
    external fun HIDDeviceReportResponse(deviceId: Int, value: ByteArray)
}
