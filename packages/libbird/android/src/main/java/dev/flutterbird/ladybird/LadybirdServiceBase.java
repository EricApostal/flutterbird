package dev.flutterbird.ladybird;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.lang.ref.WeakReference;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

abstract class LadybirdServiceBase extends Service {
    static final int MSG_SET_RESOURCE_ROOT = 1;
    static final int MSG_TRANSFER_SOCKET = 2;

    protected final String tag;
    protected volatile String resourceDir = "";

    private final ExecutorService threadPool = Executors.newCachedThreadPool();

    LadybirdServiceBase(String tag) {
        this.tag = tag;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(tag, "Creating service");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(tag, "Start command received");
        return super.onStartCommand(intent, flags, startId);
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        threadPool.shutdownNow();
        Log.i(tag, "Destroying service");
    }

    @Override
    public IBinder onBind(Intent intent) {
        return new Messenger(new IncomingHandler(this)).getBinder();
    }

    private void handleTransferSocket(Message msg) {
        Bundle data = msg.getData();
        if (data == null) {
            return;
        }
        ParcelFileDescriptor ipcSocket = data.getParcelable("IPC_SOCKET");
        if (ipcSocket == null) {
            return;
        }

        threadPool.execute(() -> nativeThreadLoop(ipcSocket.detachFd()));
    }

    private void handleSetResourceRoot(Message msg) {
        Bundle data = msg.getData();
        if (data == null) {
            return;
        }
        String root = data.getString("PATH");
        if (root == null || root.isEmpty()) {
            return;
        }
        resourceDir = root;
        initNativeCode(resourceDir, tag);
    }

    abstract boolean handleServiceSpecificMessage(Message msg);

    private native void nativeThreadLoop(int ipcSocket);

    private native void initNativeCode(String resourceDir, String tagName);

    private static final class IncomingHandler extends Handler {
        private final WeakReference<LadybirdServiceBase> service;

        IncomingHandler(LadybirdServiceBase service) {
            super(Looper.getMainLooper());
            this.service = new WeakReference<>(service);
        }

        @Override
        public void handleMessage(Message msg) {
            LadybirdServiceBase target = service.get();
            if (target == null) {
                super.handleMessage(msg);
                return;
            }

            if (msg.what == MSG_TRANSFER_SOCKET) {
                target.handleTransferSocket(msg);
                return;
            }

            if (msg.what == MSG_SET_RESOURCE_ROOT) {
                target.handleSetResourceRoot(msg);
                return;
            }

            if (!target.handleServiceSpecificMessage(msg)) {
                super.handleMessage(msg);
            }
        }
    }
}
