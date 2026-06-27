package dev.flutterbird.ladybird;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.PorterDuff;
import android.os.Handler;
import android.os.Looper;
import android.view.Surface;
import android.graphics.Rect;

import android.hardware.HardwareBuffer;
import android.graphics.ColorSpace;
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

    static {
        // SDL registers JNI methods for org.libsdl.app.* during JNI_OnLoad.
        // Load engine explicitly from Java so JNI_OnLoad has app classloader context.
        System.loadLibrary("engine");
        System.loadLibrary("ladybird_plugin");
    }

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private android.os.HandlerThread renderThread;
    private Handler renderHandler;
    private final Map<Long, TextureContext> activeTextures = new HashMap<>();

    private final android.view.Choreographer.FrameCallback frameCallback = new android.view.Choreographer.FrameCallback() {
        @Override
        public void doFrame(long frameTimeNanos) {
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
                schedulePump();
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
            LadybirdRuntimeFiles.RuntimeConfiguration runtimeConfiguration = LadybirdRuntimeFiles
                    .prepare(flutterPluginBinding.getApplicationContext());
            nativeConfigureAndroid(
                    runtimeConfiguration.resourceRoot,
                    runtimeConfiguration.userDir,
                    runtimeConfiguration.nativeLibraryDir,
                    runtimeConfiguration.certificatesPath);
        } catch (Exception exception) {
            throw new RuntimeException("Failed to prepare Ladybird Android runtime", exception);
        }

        renderThread = new android.os.HandlerThread("LadybirdRenderThread");
        renderThread.start();
        renderHandler = new Handler(renderThread.getLooper());
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
        android.view.Choreographer.getInstance().removeFrameCallback(frameCallback);
        pumpScheduled = false;

        for (TextureContext textureContext : activeTextures.values()) {
            textureContext.release();
        }
        activeTextures.clear();

        channel.setMethodCallHandler(null);
        textureRegistry = null;

        if (renderThread != null) {
            renderThread.quitSafely();
            renderThread = null;
            renderHandler = null;
        }
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
                schedulePump();
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
        diagnostics.put("frameNotifyQueued", textureContext.frameNotifyQueued);
        diagnostics.put("queuedGeneration", textureContext.lastFrameGeneration);
        diagnostics.put("lastFrameGeneration", textureContext.lastFrameGeneration);
        diagnostics.put("nativeFrameCallbacks", textureContext.nativeFrameCallbacks);
        diagnostics.put("queuedDrops", textureContext.queuedDrops);
        diagnostics.put("deliveredFrames", textureContext.deliveredFrames);
        diagnostics.put("displayLinkTicks", pumpTicks);
        diagnostics.put("pumpRequests", pumpRequests);
        diagnostics.put("pumpExecutions", pumpExecutions);
        diagnostics.put("hasDisplayLink", true);
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

        if (textureContext.frameNotifyQueued) {
            return;
        }

        if (textureContext.lastFrameGeneration > 0 && generation > textureContext.lastFrameGeneration + 1) {
            textureContext.queuedDrops += (generation - textureContext.lastFrameGeneration - 1);
        }

        int width = nativeGetSurfaceWidth(textureContext.viewId);
        int height = nativeGetSurfaceHeight(textureContext.viewId);
        if (width <= 0 || height <= 0) {
            return;
        }

        textureContext.ensureFrameStorage(width, height);

        final HardwareBuffer buffer = nativeGetHardwareBuffer(textureContext.viewId);
        if (buffer == null) {
            android.util.Log.e("LadybirdPlugin", "nativeGetHardwareBuffer returned null!");
            textureContext.queuedDrops += 1;
            return;
        }

        final Surface surface = textureContext.producer.getSurface();
        if (surface == null || !surface.isValid()) {
            android.util.Log.e("LadybirdPlugin", "Surface is null or invalid!");
            buffer.close();
            textureContext.queuedDrops += 1;
            return;
        }

        textureContext.lastFrameGeneration = generation;
        textureContext.frameNotifyQueued = true;

        if (renderHandler != null) {
            renderHandler.post(new Runnable() {
                @Override
                public void run() {
                    Canvas canvas = null;
                    try {
                        canvas = surface.lockHardwareCanvas();
                        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR);
                        Bitmap bitmap = Bitmap.wrapHardwareBuffer(buffer, ColorSpace.get(ColorSpace.Named.SRGB));
                        if (bitmap != null) {
                            Rect src = new Rect(0, 0, width, height);
                            Rect dst = new Rect(0, 0, width, height);
                            canvas.drawBitmap(bitmap, src, dst, null);
                        } else {
                            android.util.Log.e("LadybirdPlugin", "Bitmap.wrapHardwareBuffer returned null!");
                        }
                        textureContext.deliveredFrames += 1;
                    } catch (RuntimeException exception) {
                        android.util.Log.e("LadybirdPlugin", "Exception drawing hardware buffer", exception);
                        textureContext.queuedDrops += 1;
                    } finally {
                        if (canvas != null) {
                            surface.unlockCanvasAndPost(canvas);
                        }
                        buffer.close();
                        textureContext.frameNotifyQueued = false;
                    }
                }
            });
        } else {
            buffer.close();
            textureContext.frameNotifyQueued = false;
        }
    }

    private void updatePumpDriver() {
        if (activeTextures.isEmpty()) {
            android.view.Choreographer.getInstance().removeFrameCallback(frameCallback);
            pumpScheduled = false;
            return;
        }

        schedulePump();
    }

    private void schedulePump() {
        if (pumpScheduled) {
            return;
        }

        pumpScheduled = true;
        pumpRequests += 1;
        android.view.Choreographer.getInstance().postFrameCallback(frameCallback);
    }

    private static final class TextureContext {
        final int viewId;
        final TextureRegistry.SurfaceProducer producer;
        final long textureId;

        boolean active = true;
        volatile boolean frameNotifyQueued = false;
        int width = 0;
        int height = 0;
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
            if (nextWidth == width && nextHeight == height) {
                return;
            }

            width = nextWidth;
            height = nextHeight;
            producer.setSize(width, height);
        }

        void release() {
            active = false;
            producer.release();
        }
    }

    private static native void nativeConfigureAndroid(
            String resourceRoot,
            String userDir,
            String nativeLibraryDir,
            String certificatesPath);

    private static native void nativeTickLadybird();

    private static native long nativeGetFrameGeneration(int viewId);

    private static native int nativeGetSurfaceWidth(int viewId);

    private static native int nativeGetSurfaceHeight(int viewId);

    private static native HardwareBuffer nativeGetHardwareBuffer(int viewId);
}