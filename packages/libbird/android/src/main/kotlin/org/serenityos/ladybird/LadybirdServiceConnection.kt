package org.serenityos.ladybird

import android.content.ComponentName
import android.content.ServiceConnection
import android.os.IBinder
import android.os.Message
import android.os.Messenger
import android.os.ParcelFileDescriptor

class LadybirdServiceConnection(
  private var ipcFd: Int,
  private val resourceDir: String,
) : ServiceConnection {
  var onDisconnect: () -> Unit = {}
  private var service: Messenger? = null

  override fun onServiceConnected(name: ComponentName, binder: IBinder) {
    service = Messenger(binder)

    val init = Message.obtain(null, MSG_SET_RESOURCE_ROOT)
    init.data.putString("PATH", resourceDir)
    service?.send(init)

    val parcel = ParcelFileDescriptor.adoptFd(ipcFd)
    val transfer = Message.obtain(null, MSG_TRANSFER_SOCKET)
    transfer.data.putParcelable("IPC_SOCKET", parcel)
    service?.send(transfer)
    parcel.detachFd()
  }

  override fun onServiceDisconnected(name: ComponentName) {
    service = null
    onDisconnect()
  }
}
