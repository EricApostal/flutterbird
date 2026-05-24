package dev.flutterbird.ladybird;

import android.content.ComponentName;
import android.content.ServiceConnection;
import android.os.IBinder;
import android.os.Message;
import android.os.Messenger;
import android.os.ParcelFileDescriptor;

class LadybirdServiceConnection implements ServiceConnection {
    private final int ipcFd;
    private final String resourceDir;

    Runnable onDisconnect = () -> {
    };

    private Messenger service;

    LadybirdServiceConnection(int ipcFd, String resourceDir) {
        this.ipcFd = ipcFd;
        this.resourceDir = resourceDir;
    }

    @Override
    public void onServiceConnected(ComponentName className, IBinder binder) {
        service = new Messenger(binder);

        try {
            Message initMessage = Message.obtain(null, LadybirdServiceBase.MSG_SET_RESOURCE_ROOT);
            initMessage.getData().putString("PATH", resourceDir);
            service.send(initMessage);

            ParcelFileDescriptor parcel = ParcelFileDescriptor.adoptFd(ipcFd);
            Message socketMessage = Message.obtain(null, LadybirdServiceBase.MSG_TRANSFER_SOCKET);
            socketMessage.getData().putParcelable("IPC_SOCKET", parcel);
            service.send(socketMessage);
            parcel.detachFd();
        } catch (Exception ignored) {
            onDisconnect.run();
        }
    }

    @Override
    public void onServiceDisconnected(ComponentName className) {
        service = null;
        onDisconnect.run();
    }
}
