package dev.flutterbird.ladybird;

import android.content.Context;
import android.content.Intent;
import android.os.Message;
import android.util.Log;

public final class WebContentService extends LadybirdServiceBase {
    public WebContentService() {
        super("WebContentService");
        nativeInit();
    }

    @Override
    boolean handleServiceSpecificMessage(Message msg) {
        return false;
    }

    private void bindRequestServer(int ipcFd) {
        LadybirdServiceConnection connector = new LadybirdServiceConnection(ipcFd, resourceDir);
        connector.onDisconnect = () -> Log.e(tag, "RequestServer disconnected");
        bindService(
                new Intent(this, RequestServerService.class),
                connector,
                Context.BIND_AUTO_CREATE);
    }

    private void bindImageDecoder(int ipcFd) {
        LadybirdServiceConnection connector = new LadybirdServiceConnection(ipcFd, resourceDir);
        connector.onDisconnect = () -> Log.e(tag, "ImageDecoder disconnected");
        bindService(
                new Intent(this, ImageDecoderService.class),
                connector,
                Context.BIND_AUTO_CREATE);
    }

    private void bindCompositor(int ipcFd) {
        LadybirdServiceConnection connector = new LadybirdServiceConnection(ipcFd, resourceDir);
        connector.onDisconnect = () -> Log.e(tag, "Compositor disconnected");
        bindService(
                new Intent(this, CompositorService.class),
                connector,
                Context.BIND_AUTO_CREATE);
    }

    private native void nativeInit();

    static {
        System.loadLibrary("webcontentservice");
    }
}
