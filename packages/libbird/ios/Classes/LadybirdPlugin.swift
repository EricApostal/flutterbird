import UIKit
import CoreVideo
import Flutter

private let assumedPumpInterval = 1.0 / 120.0
private let generationResetThreshold: UInt64 = 256
private let queueStallGenerationThreshold: UInt64 = 120

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

  static var debugCopyCount = 0

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let ptr = get_latest_pixel_buffer(viewId) else {
      if LadybirdTexture.debugCopyCount < 5 {
        LadybirdTexture.debugCopyCount += 1
        print("[Ladybird][iOS] copyPixelBuffer view=\(viewId) -> nil (no buffer)")
      }
      return nil
    }
    let buffer = Unmanaged<CVPixelBuffer>.fromOpaque(ptr).takeRetainedValue()
    if LadybirdTexture.debugCopyCount < 5 {
      LadybirdTexture.debugCopyCount += 1
      let w = CVPixelBufferGetWidth(buffer)
      let h = CVPixelBufferGetHeight(buffer)
      let fmt = CVPixelBufferGetPixelFormatType(buffer)
      print("[Ladybird][iOS] copyPixelBuffer view=\(viewId) -> \(w)x\(h) fmt=\(fmt)")
    }
    return Unmanaged.passRetained(buffer)
  }
}

class TextureContext {
  let registry: FlutterTextureRegistry
  let textureId: Int64
  let viewId: Int32
  let stateLock = NSLock()
  var frameNotifyQueued = false
  var queuedGeneration: UInt64 = 0
  var lastFrameGeneration: UInt64 = 0
  var isActive = true
  var nativeFrameCallbacks: UInt64 = 0
  var queuedDrops: UInt64 = 0
  var deliveredFrames: UInt64 = 0

  init(registry: FlutterTextureRegistry, textureId: Int64, viewId: Int32) {
    self.registry = registry
    self.textureId = textureId
    self.viewId = viewId
  }
}

public class LadybirdPluginSwift: NSObject, FlutterPlugin {
  var textureRegistry: FlutterTextureRegistry?
  var runLoopObserver: CFRunLoopObserver?
  var displayLink: CADisplayLink?
  var pumpTimer: Timer?
  var contextPtrs: [Int64: UnsafeMutableRawPointer] = [:]
  var activeTexturesForView: [Int32: Int64] = [:]
  private let pumpStateLock = NSLock()
  private var displayLinkTicks: UInt64 = 0
  private var pumpRequests: UInt64 = 0
  private var pumpExecutions: UInt64 = 0
  private var pumpInProgress = false
  private var pumpRequested = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ladybird", binaryMessenger: registrar.messenger())
    let instance = LadybirdPluginSwift()
    instance.textureRegistry = registrar.textures()
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
      guard let self, self.displayLink == nil else { return }
      self.requestLadybirdPump()
    }

    guard let observer else { return }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    runLoopObserver = observer
  }

  deinit {
    stopDisplayLink()
    stopPumpTimer()
    if let observer = runLoopObserver {
      CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
      runLoopObserver = nil
    }
  }

  private func updatePumpDriver() {
    let needsDisplayLink = !activeTexturesForView.isEmpty

    if needsDisplayLink {
      stopDisplayLink()
      startPumpTimer()
      requestLadybirdPump()
      return
    }

    stopDisplayLink()
    stopPumpTimer()
  }

  private func startPumpTimer() {
    guard pumpTimer == nil else { return }

    let timer = Timer(timeInterval: assumedPumpInterval, repeats: true) {
      [weak self] _ in
      self?.requestLadybirdPump()
    }
    timer.tolerance = assumedPumpInterval * 0.1
    RunLoop.main.add(timer, forMode: .common)
    pumpTimer = timer
  }

  private func stopPumpTimer() {
    pumpTimer?.invalidate()
    pumpTimer = nil
  }

  private func stopDisplayLink() {
    guard let displayLink else { return }
    displayLink.invalidate()
    self.displayLink = nil
  }

  private func requestLadybirdPump() {
    pumpStateLock.lock()
    pumpRequests += 1
    if pumpInProgress {
      pumpRequested = true
      pumpStateLock.unlock()
      return
    }
    pumpInProgress = true
    pumpStateLock.unlock()

    while true {
      pumpStateLock.lock()
      pumpExecutions += 1
      pumpStateLock.unlock()

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
      updatePumpDriver()
      print("[Ladybird][iOS] createTexture view=\(viewId) textureId=\(textureId) ctx=\(ctxPtr)")

      let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { contextPtr in
        guard let contextPtr = contextPtr else { return }
        let ctx = Unmanaged<TextureContext>.fromOpaque(contextPtr).takeUnretainedValue()

        let generation = get_frame_generation(ctx.viewId)

        ctx.stateLock.lock()
        ctx.nativeFrameCallbacks += 1
        if !ctx.isActive {
          ctx.stateLock.unlock()
          return
        }
        if generation != 0 && generation <= ctx.lastFrameGeneration {
          if generation < ctx.lastFrameGeneration {
            let delta = ctx.lastFrameGeneration - generation
            if delta > generationResetThreshold {
              print(
                "[Ladybird][iOS] generation reset detected for view \(ctx.viewId) (generation=\(generation) last=\(ctx.lastFrameGeneration)); accepting new sequence"
              )
            } else {
              print(
                "[Ladybird][iOS] dropping out-of-order frame for view \(ctx.viewId) (generation=\(generation) < last=\(ctx.lastFrameGeneration))"
              )
              ctx.stateLock.unlock()
              return
            }
          } else {
            ctx.stateLock.unlock()
            return
          }
        }
        if generation != 0 {
          ctx.lastFrameGeneration = generation
        }
        if ctx.frameNotifyQueued {
          if generation != 0 && generation > ctx.queuedGeneration + queueStallGenerationThreshold {
            print(
              "[Ladybird][iOS] queue stall detected for view \(ctx.viewId) (generation=\(generation) queuedAt=\(ctx.queuedGeneration)); resetting notify latch"
            )
            ctx.frameNotifyQueued = false
          }
        }
        if ctx.frameNotifyQueued {
          ctx.queuedDrops += 1
          if (ctx.queuedDrops % 120) == 1 {
            print(
              "[Ladybird][iOS] frame callback coalesced view=\(ctx.viewId) textureId=\(ctx.textureId) queuedDrops=\(ctx.queuedDrops) generation=\(generation)"
            )
          }
          ctx.stateLock.unlock()
          return
        }
        ctx.frameNotifyQueued = true
        ctx.queuedGeneration = generation

        if (ctx.nativeFrameCallbacks % 120) == 1 {
          print(
            "[Ladybird][iOS] native frame callback view=\(ctx.viewId) textureId=\(ctx.textureId) callbacks=\(ctx.nativeFrameCallbacks) generation=\(generation) queued=\(ctx.frameNotifyQueued)"
          )
        }
        ctx.stateLock.unlock()

        let textureId = ctx.textureId
        let reg = ctx.registry

        let deliverFrameAvailable = {
          ctx.stateLock.lock()
          let isActive = ctx.isActive
          ctx.frameNotifyQueued = false
          if isActive {
            ctx.deliveredFrames += 1
            if (ctx.deliveredFrames % 120) == 1 {
              print(
                "[Ladybird][iOS] textureFrameAvailable view=\(ctx.viewId) textureId=\(ctx.textureId) delivered=\(ctx.deliveredFrames) lastGeneration=\(ctx.lastFrameGeneration)"
              )
            }
          }
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
    case "getTextureDiagnostics":
      guard let num = call.arguments as? NSNumber else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected texture ID", details: nil))
        return
      }

      let textureId = num.int64Value
      guard let ptr = contextPtrs[textureId] else {
        result(nil)
        return
      }

      let ctx = Unmanaged<TextureContext>.fromOpaque(ptr).takeUnretainedValue()
      ctx.stateLock.lock()
      let diagnostics: [String: Any] = [
        "textureId": textureId,
        "viewId": Int(ctx.viewId),
        "isActive": ctx.isActive,
        "frameNotifyQueued": ctx.frameNotifyQueued,
        "queuedGeneration": Int64(ctx.queuedGeneration),
        "lastFrameGeneration": Int64(ctx.lastFrameGeneration),
        "nativeFrameCallbacks": Int64(ctx.nativeFrameCallbacks),
        "queuedDrops": Int64(ctx.queuedDrops),
        "deliveredFrames": Int64(ctx.deliveredFrames),
      ]
      ctx.stateLock.unlock()

      pumpStateLock.lock()
      let driverDiagnostics: [String: Any] = [
        "displayLinkTicks": Int64(displayLinkTicks),
        "pumpRequests": Int64(pumpRequests),
        "pumpExecutions": Int64(pumpExecutions),
        "hasDisplayLink": displayLink != nil,
      ]
      pumpStateLock.unlock()

      result(diagnostics.merging(driverDiagnostics) { _, new in new })
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
      print("[Ladybird][iOS] unregisterTexture textureId=\(textureId)")

      if let ptr = contextPtrs.removeValue(forKey: textureId) {
        let ctx = Unmanaged<TextureContext>.fromOpaque(ptr).takeRetainedValue()
        ctx.stateLock.lock()
        ctx.isActive = false
        ctx.frameNotifyQueued = false
        ctx.stateLock.unlock()

        if activeTexturesForView[ctx.viewId] == textureId {
          print(
            "[Ladybird][iOS] clearing frame callback for active view=\(ctx.viewId) textureId=\(textureId)"
          )
          set_frame_callback(ctx.viewId, nil, nil)
          activeTexturesForView.removeValue(forKey: ctx.viewId)
        } else {
          let active = activeTexturesForView[ctx.viewId] ?? -1
          print(
            "[Ladybird][iOS] keeping frame callback view=\(ctx.viewId) removedTexture=\(textureId) activeTexture=\(active)"
          )
        }

        self.updatePumpDriver()
      }

      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
