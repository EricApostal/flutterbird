import Cocoa
import FlutterMacOS

@_silgen_name("get_latest_pixel_buffer")
func get_latest_pixel_buffer(_ view_id: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("tick_ladybird")
func tick_ladybird()

@_silgen_name("get_frame_generation")
func get_frame_generation(_ view_id: Int32) -> UInt64

@_silgen_name("set_frame_callback")
func set_frame_callback(
  _ view_id: Int32, _ callback: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?,
  _ context: UnsafeMutableRawPointer?
)

class LadybirdTexture: NSObject, FlutterTexture {
  let viewId: Int32

  init(viewId: Int32) {
    self.viewId = viewId
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let ptr = get_latest_pixel_buffer(viewId) else {
      return nil
    }
    let buffer = Unmanaged<CVPixelBuffer>.fromOpaque(ptr).takeRetainedValue()
    return Unmanaged.passRetained(buffer)
  }
}

class TextureContext {
  let registry: FlutterTextureRegistry
  let textureId: Int64
  let viewId: Int32
  let stateLock = NSLock()
  var frameNotifyQueued = false
  var lastFrameGeneration: UInt64 = 0
  var isActive = true

  init(registry: FlutterTextureRegistry, textureId: Int64, viewId: Int32) {
    self.registry = registry
    self.textureId = textureId
    self.viewId = viewId
  }
}

public class LadybirdPlugin: NSObject, FlutterPlugin {
  var textureRegistry: FlutterTextureRegistry?
  var runLoopObserver: CFRunLoopObserver?
  var contextPtrs: [Int64: UnsafeMutableRawPointer] = [:]
  var activeTexturesForView: [Int32: Int64] = [:]
  private let pumpStateLock = NSLock()
  private var pumpInProgress = false
  private var pumpRequested = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ladybird", binaryMessenger: registrar.messenger)
    let instance = LadybirdPlugin()
    instance.textureRegistry = registrar.textures
    registrar.addMethodCallDelegate(instance, channel: channel)

    instance.startLadybirdLoop()
  }

  private func startLadybirdLoop() {
    let activities =
      CFRunLoopActivity.beforeSources.rawValue
      | CFRunLoopActivity.beforeWaiting.rawValue
      | CFRunLoopActivity.afterWaiting.rawValue

    let observer = CFRunLoopObserverCreateWithHandler(
      kCFAllocatorDefault,
      activities,
      true,
      0
    ) { [weak self] _, _ in
      self?.requestLadybirdPump()
    }

    guard let observer else { return }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    runLoopObserver = observer

    // Prime one pass at startup.
    requestLadybirdPump()
  }

  deinit {
    if let observer = runLoopObserver {
      CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
      runLoopObserver = nil
    }
  }

  private func requestLadybirdPump() {
    pumpStateLock.lock()
    if pumpInProgress {
      pumpRequested = true
      pumpStateLock.unlock()
      return
    }
    pumpInProgress = true
    pumpStateLock.unlock()

    while true {
      tick_ladybird()

      pumpStateLock.lock()
      if pumpRequested {
        pumpRequested = false
        pumpStateLock.unlock()
        continue
      }
      pumpInProgress = false
      pumpStateLock.unlock()
      break
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createTexture":

      guard let registry = textureRegistry else {
        result(FlutterError(code: "UNAVAILABLE", message: "Texture registry is null", details: nil))
        return
      }

      guard let num = call.arguments as? NSNumber else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected view ID", details: nil))
        return
      }
      let viewId = num.int32Value

      let texture = LadybirdTexture(viewId: viewId)
      let textureId = registry.register(texture)

      let ctx = TextureContext(registry: registry, textureId: textureId, viewId: viewId)

      let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()
      contextPtrs[textureId] = ctxPtr
      activeTexturesForView[viewId] = textureId

      let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { contextPtr in
        guard let contextPtr = contextPtr else { return }
        let ctx = Unmanaged<TextureContext>.fromOpaque(contextPtr).takeUnretainedValue()

        let generation = get_frame_generation(ctx.viewId)

        ctx.stateLock.lock()
        if !ctx.isActive {
          ctx.stateLock.unlock()
          return
        }
        if generation != 0 && generation <= ctx.lastFrameGeneration {
          if generation < ctx.lastFrameGeneration {
            NSLog(
              "[Ladybird][macOS] dropping out-of-order frame for view %d (generation=%llu < last=%llu)",
              ctx.viewId,
              generation,
              ctx.lastFrameGeneration
            )
          }
          ctx.stateLock.unlock()
          return
        }
        ctx.lastFrameGeneration = generation
        if ctx.frameNotifyQueued {
          ctx.stateLock.unlock()
          return
        }
        ctx.frameNotifyQueued = true
        ctx.stateLock.unlock()

        let textureId = ctx.textureId
        let reg = ctx.registry

        let deliverFrameAvailable = {
          ctx.stateLock.lock()
          let isActive = ctx.isActive
          ctx.frameNotifyQueued = false
          ctx.stateLock.unlock()

          guard isActive else { return }
          reg.textureFrameAvailable(textureId)
        }

        if Thread.isMainThread {
          deliverFrameAvailable()
        } else {
          DispatchQueue.main.async(execute: deliverFrameAvailable)
        }
      }

      set_frame_callback(viewId, callback, ctxPtr)

      result(textureId)
    case "unregisterTexture":
      guard let registry = textureRegistry else {
        result(FlutterError(code: "UNAVAILABLE", message: "Texture registry is null", details: nil))
        return
      }
      guard let num = call.arguments as? NSNumber else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected texture ID", details: nil))
        return
      }
      let textureId = num.int64Value
      registry.unregisterTexture(textureId)

      if let ptr = contextPtrs.removeValue(forKey: textureId) {
        let ctx = Unmanaged<TextureContext>.fromOpaque(ptr).takeRetainedValue()
        ctx.stateLock.lock()
        ctx.isActive = false
        ctx.frameNotifyQueued = false
        ctx.stateLock.unlock()

        if activeTexturesForView[ctx.viewId] == textureId {
          set_frame_callback(ctx.viewId, nil, nil)
          activeTexturesForView.removeValue(forKey: ctx.viewId)
        }
      }

      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
