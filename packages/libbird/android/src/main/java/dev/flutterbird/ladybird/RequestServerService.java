package dev.flutterbird.ladybird;

import android.os.Message;

public final class RequestServerService extends LadybirdServiceBase {
    public RequestServerService() {
        super("RequestServerService");
    }

    @Override
    boolean handleServiceSpecificMessage(Message msg) {
        return false;
    }

    static {
        System.loadLibrary("requestserverservice");
    }
}
