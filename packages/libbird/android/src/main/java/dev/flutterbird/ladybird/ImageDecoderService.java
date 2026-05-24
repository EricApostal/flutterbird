package dev.flutterbird.ladybird;

import android.os.Message;

public final class ImageDecoderService extends LadybirdServiceBase {
    public ImageDecoderService() {
        super("ImageDecoderService");
    }

    @Override
    boolean handleServiceSpecificMessage(Message msg) {
        return false;
    }

    static {
        System.loadLibrary("imagedecoderservice");
    }
}
