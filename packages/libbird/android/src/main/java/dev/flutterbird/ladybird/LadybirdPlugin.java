package dev.flutterbird.ladybird;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.PorterDuff;
import android.os.Handler;
import android.os.Looper;
import android.view.Surface;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.view.TextureRegistry;

public final class LadybirdPlugin implements FlutterPlugin, MethodCallHandler {
    private static final long PUMP_INTERVAL_MS = 16L;

    static {
        System.loadLibrary("ladybird_plugin");
    }

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Map<Long, TextureContext> activeTextures = new HashMap<>();
    private final Runnable pumpRunnable = new Runnable() {
        @Override
        public void run() {
            pumpScheduled = false;
            if (activeTextures.isEmpty()) {
                return;
            }

            pumpExecutions += 1;
            pumpTicks += 1;
            nativeTickLadybird();

            for (TextureContext textureContext : new ArrayList<>(activeTextures.values())) {
                renderLatestFrame(textureContext);
            }

            if (!activeTextures.isEmpty()) {
                schedulePump(PUMP_INTERVAL_MS);
            }
        }
    };

    private MethodChannel channel;
    private TextureRegistry textureRegistry;
    private boolean pumpScheduled = false;
    private long pumpRequests = 0;
    private long pumpExecutions = 0;
    private long pumpTicks = 0;

    @Override
    public void onAttachedToEngine(FlutterPlugin.FlutterPluginBinding flutterPluginBinding) {
        textureRegistry = flutterPluginBinding.getTextureRegistry();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "ladybird");
        channel.setMethodCallHandler(this);

        try {
            LadybirdRuntimeFiles.RuntimeConfiguration runtimeConfiguration =
                    LadybirdRuntimeFiles.prepare(flutterPluginBinding.getApplicationContext());
            nativeConfigureAndroid(
                    runtimeConfiguration.resourceRoot,
                    runtimeConfiguration.userDir,
                    runtimeConfiguration.nativeLibraryDir,
                    runtimeConfiguration.certificatesPath);
        } catch (Exception exception) {
            throw new RuntimeException("Failed to prepare Ladybird Android runtime", exception);
        }
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        switch (call.method) {
            case "createTexture":
                createTexture(call, result);
                return;
            case "unregisterTexture":
                unregisterTexture(call, result);
                return;
            case "getTextureDiagnostics":
                getTextureDiagnostics(call, result);
                return;
            default:
                result.notImplemented();
        }
    }

    @Override
    public void onDetachedFromEngine(FlutterPlugin.FlutterPluginBinding binding) {
        mainHandler.removeCallbacks(pumpRunnable);
        pumpScheduled = false;

        for (TextureContext textureContext : activeTextures.values()) {
            textureContext.release();
        }
        activeTextures.clear();

        channel.setMethodCallHandler(null);
        textureRegistry = null;
    }

    private void createTexture(MethodCall call, Result result) {
        if (!(call.arguments instanceof Number) || textureRegistry == null) {
            result.error("INVALID_ARGS", "Expected numeric view ID", null);
            return;
        }

        int viewId = ((Number) call.arguments).intValue();
        TextureRegistry.SurfaceProducer producer = textureRegistry.createSurfaceProducer();
        TextureContext textureContext = new TextureContext(viewId, producer);
        producer.setCallback(new TextureRegistry.SurfaceProducer.Callback() {
            @Override
            public void onSurfaceDestroyed() {
            }

            @Override
            public void onSurfaceAvailable() {
                schedulePump(0L);
            }
        });

        activeTextures.put(textureContext.textureId, textureContext);
        renderLatestFrame(textureContext);
        updatePumpDriver();
        result.success(textureContext.textureId);
    }

    private void unregisterTexture(MethodCall call, Result result) {
        if (!(call.arguments instanceof Number)) {
            result.error("INVALID_ARGS", "Expected numeric texture ID", null);
            return;
        }

        long textureId = ((Number) call.arguments).longValue();
        TextureContext textureContext = activeTextures.remove(textureId);
        if (textureContext != null) {
            textureContext.release();
        }

        updatePumpDriver();
        result.success(null);
    }

    private void getTextureDiagnostics(MethodCall call, Result result) {
        if (!(call.arguments instanceof Number)) {
            result.error("INVALID_ARGS", "Expected numeric texture ID", null);
            return;
        }

        long textureId = ((Number) call.arguments).longValue();
        TextureContext textureContext = activeTextures.get(textureId);
        if (textureContext == null) {
            result.success(null);
            return;
        }

        Map<String, Object> diagnostics = new HashMap<>();
        diagnostics.put("textureId", textureContext.textureId);
        diagnostics.put("viewId", textureContext.viewId);
        diagnostics.put("isActive", textureContext.active);
        diagnostics.put("frameNotifyQueued", false);
        diagnostics.put("queuedGeneration", textureContext.lastFrameGeneration);
        diagnostics.put("lastFrameGeneration", textureContext.lastFrameGeneration);
        diagnostics.put("nativeFrameCallbacks", textureContext.nativeFrameCallbacks);
        diagnostics.put("queuedDrops", textureContext.queuedDrops);
        diagnostics.put("deliveredFrames", textureContext.deliveredFrames);
        diagnostics.put("displayLinkTicks", pumpTicks);
        diagnostics.put("pumpRequests", pumpRequests);
        diagnostics.put("pumpExecutions", pumpExecutions);
        diagnostics.put("hasDisplayLink", false);
        result.success(diagnostics);
    }

    private void renderLatestFrame(TextureContext textureContext) {
        if (!textureContext.active) {
            return;
        }

        long generation = nativeGetFrameGeneration(textureContext.viewId);
        textureContext.nativeFrameCallbacks += 1;
        if (generation == 0 || generation == textureContext.lastFrameGeneration) {
            return;
        }

        int width = nativeGetSurfaceWidth(textureContext.viewId);
        int height = nativeGetSurfaceHeight(textureContext.viewId);
        if (width <= 0 || height <= 0) {
            return;
        }

        textureContext.ensureFrameStorage(width, height);
        textureContext.pixelBuffer.rewind();
        if (!nativeCopyLatestPixelBuffer(
                textureContext.viewId,
                textureContext.pixelBuffer,
                textureContext.pixelBuffer.capacity())) {
            textureContext.queuedDrops += 1;
            return;
        }

        textureContext.pixelBuffer.rewind();
        textureContext.bitmap.copyPixelsFromBuffer(textureContext.pixelBuffer);
        textureContext.pixelBuffer.rewind();
        textureContext.lastFrameGeneration = generation;

        Surface surface = textureContext.producer.getSurface();
        if (surface == null || !surface.isValid()) {
            textureContext.queuedDrops += 1;
            return;
        }

        Canvas canvas = null;
        try {
            canvas = surface.lockCanvas(null);
            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR);
            canvas.drawBitmap(textureContext.bitmap, 0f, 0f, null);
            textureContext.deliveredFrames += 1;
        } catch (RuntimeException exception) {
            textureContext.queuedDrops += 1;
        } finally {
            if (canvas != null) {
                surface.unlockCanvasAndPost(canvas);
            }
        }
    }

    private void updatePumpDriver() {
        if (activeTextures.isEmpty()) {
            mainHandler.removeCallbacks(pumpRunnable);
            pumpScheduled = false;
            return;
        }

        schedulePump(0L);
    }

    private void schedulePump(long delayMillis) {
        if (pumpScheduled) {
            return;
        }

        pumpScheduled = true;
        pumpRequests += 1;
        if (delayMillis <= 0L) {
            mainHandler.post(pumpRunnable);
        } else {
            mainHandler.postDelayed(pumpRunnable, delayMillis);
        }
    }

    private static final class TextureContext {
        final int viewId;
        final TextureRegistry.SurfaceProducer producer;
        final long textureId;

        boolean active = true;
        int width = 0;
        int height = 0;
        Bitmap bitmap;
        ByteBuffer pixelBuffer;
        long lastFrameGeneration = 0;
        long nativeFrameCallbacks = 0;
        long queuedDrops = 0;
        long deliveredFrames = 0;

        TextureContext(int viewId, TextureRegistry.SurfaceProducer producer) {
            this.viewId = viewId;
            this.producer = producer;
            this.textureId = producer.id();
        }

        void ensureFrameStorage(int nextWidth, int nextHeight) {
            if (nextWidth == width && nextHeight == height && bitmap != null && pixelBuffer != null) {
                return;
            }

            width = nextWidth;
            height = nextHeight;
            producer.setSize(width, height);
            bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            pixelBuffer = ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder());
        }

        void release() {
            active = false;
            producer.release();
            bitmap = null;
            pixelBuffer = null;
        }
    }

    private static native void nativeConfigureAndroid(
            String resourceRoot,
            String userDir,
            String nativeLibraryDir,
            String certificatesPath
    );

    private static native void nativeTickLadybird();

    private static native long nativeGetFrameGeneration(int viewId);

    private static native int nativeGetSurfaceWidth(int viewId);

    private static native int nativeGetSurfaceHeight(int viewId);

    private static native boolean nativeCopyLatestPixelBuffer(
            int viewId,
            ByteBuffer pixelBuffer,
            int capacity
    );
}