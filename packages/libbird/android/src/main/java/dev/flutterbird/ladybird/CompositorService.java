package dev.flutterbird.ladybird;

import android.os.Message;

public final class CompositorService extends LadybirdServiceBase {
    public CompositorService() {
        super("CompositorService");
    }

    @Override
    boolean handleServiceSpecificMessage(Message msg) {
        return false;
    }

    static {
        System.loadLibrary("compositorservicebridge");
    }
}
