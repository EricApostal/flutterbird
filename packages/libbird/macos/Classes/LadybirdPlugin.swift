import Cocoa
import CoreVideo
import FlutterMacOS
import IOSurface
import Metal

private let assumedPumpInterval = 1.0 / 144.0
private let generationResetThreshold: UInt64 = 256
private let queueStallGenerationThreshold: UInt64 = 120

@_silgen_name("get_latest_pixel_buffer")
func get_latest_pixel_buffer(_ view_id: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("get_latest_iosurface")
func get_latest_iosurface(_ view_id: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("get_last_painted_width")
func get_last_painted_width(_ view_id: Int32) -> Int32

@_silgen_name("get_last_painted_height")
func get_last_painted_height(_ view_id: Int32) -> Int32

@_silgen_name("tick_ladybird")
func tick_ladybird()

@_silgen_name("get_frame_generation")
func get_frame_generation(_ view_id: Int32) -> UInt64

@_silgen_name("set_frame_callback")
func set_frame_callback(
  _ view_id: Int32, _ callback: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?,
  _ context: UnsafeMutableRawPointer?
)

private final class MetalIOSurfaceCropper {
  static let shared = MetalIOSurfaceCropper()

  private let device: MTLDevice?
  private let queue: MTLCommandQueue?

  private init() {
    device = MTLCreateSystemDefaultDevice()
    queue = device?.makeCommandQueue()
  }

  func crop(surface: IOSurface, width: Int, height: Int) -> CVPixelBuffer? {
    guard let device = device, let queue = queue, width > 0, height > 0 else {
      return nil
    }

    let surfaceWidth = IOSurfaceGetWidth(surface)
    let surfaceHeight = IOSurfaceGetHeight(surface)
    guard surfaceWidth > 0, surfaceHeight > 0 else {
      return nil
    }
    let cropWidth = min(width, surfaceWidth)
    let cropHeight = min(height, surfaceHeight)

    let srcDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: cropWidth, height: cropHeight, mipmapped: false)
    srcDescriptor.usage = [.shaderRead]
    guard
      let srcTexture = device.makeTexture(
        descriptor: srcDescriptor, iosurface: surface, plane: 0)
    else {
      return nil
    }

    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    let createResult = CVPixelBufferCreate(
      kCFAllocatorDefault, cropWidth, cropHeight, kCVPixelFormatType_32BGRA,
      attributes as CFDictionary, &pixelBuffer)
    guard createResult == kCVReturnSuccess, let pixelBuffer = pixelBuffer,
      let dstSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
    else {
      return nil
    }

    let dstDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: cropWidth, height: cropHeight, mipmapped: false)
    dstDescriptor.usage = [.shaderWrite]
    guard
      let dstTexture = device.makeTexture(
        descriptor: dstDescriptor, iosurface: dstSurface, plane: 0),
      let commandBuffer = queue.makeCommandBuffer(),
      let blit = commandBuffer.makeBlitCommandEncoder()
    else {
      return nil
    }

    blit.copy(
      from: srcTexture, sourceSlice: 0, sourceLevel: 0,
      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
      sourceSize: MTLSize(width: cropWidth, height: cropHeight, depth: 1),
      to: dstTexture, destinationSlice: 0, destinationLevel: 0,
      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
    blit.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    return pixelBuffer
  }
}

class LadybirdTexture: NSObject, FlutterTexture {
  let viewId: Int32

  init(viewId: Int32) {
    self.viewId = viewId
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    // Primary path: crop the IOSurface to last_painted_size via a GPU blit.
    if let surfacePtr = get_latest_iosurface(viewId) {
      let surface = Unmanaged<IOSurface>.fromOpaque(surfacePtr).takeRetainedValue()
      let paintedWidth = Int(get_last_painted_width(viewId))
      let paintedHeight = Int(get_last_painted_height(viewId))
      if let cropped = MetalIOSurfaceCropper.shared.crop(
        surface: surface, width: paintedWidth, height: paintedHeight)
      {
        return Unmanaged.passRetained(cropped)
      }
    }

    // CPU bitmap fallback (used before the IOSurface path has a frame yet,
    // or on the non-IOSurface rendering path).
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

public class LadybirdPlugin: NSObject, FlutterPlugin {
  var textureRegistry: FlutterTextureRegistry?
  var runLoopObserver: CFRunLoopObserver?
  var displayLink: CVDisplayLink?
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
    CVDisplayLinkStop(displayLink)
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
      print("[Ladybird][macOS] createTexture view=\(viewId) textureId=\(textureId) ctx=\(ctxPtr)")

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
                "[Ladybird][macOS] generation reset detected for view \(ctx.viewId) (generation=\(generation) last=\(ctx.lastFrameGeneration)); accepting new sequence"
              )
            } else {
              print(
                "[Ladybird][macOS] dropping out-of-order frame for view \(ctx.viewId) (generation=\(generation) < last=\(ctx.lastFrameGeneration))"
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
              "[Ladybird][macOS] queue stall detected for view \(ctx.viewId) (generation=\(generation) queuedAt=\(ctx.queuedGeneration)); resetting notify latch"
            )
            ctx.frameNotifyQueued = false
          }
        }
        if ctx.frameNotifyQueued {
          ctx.queuedDrops += 1
          if (ctx.queuedDrops % 120) == 1 {
            print(
              "[Ladybird][macOS] frame callback coalesced view=\(ctx.viewId) textureId=\(ctx.textureId) queuedDrops=\(ctx.queuedDrops) generation=\(generation)"
            )
          }
          ctx.stateLock.unlock()
          return
        }
        ctx.frameNotifyQueued = true
        ctx.queuedGeneration = generation

        if (ctx.nativeFrameCallbacks % 120) == 1 {
          print(
            "[Ladybird][macOS] native frame callback view=\(ctx.viewId) textureId=\(ctx.textureId) callbacks=\(ctx.nativeFrameCallbacks) generation=\(generation) queued=\(ctx.frameNotifyQueued)"
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
                "[Ladybird][macOS] textureFrameAvailable view=\(ctx.viewId) textureId=\(ctx.textureId) delivered=\(ctx.deliveredFrames) lastGeneration=\(ctx.lastFrameGeneration)"
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
      print("[Ladybird][macOS] unregisterTexture textureId=\(textureId)")

      if let ptr = contextPtrs.removeValue(forKey: textureId) {
        let ctx = Unmanaged<TextureContext>.fromOpaque(ptr).takeRetainedValue()
        ctx.stateLock.lock()
        ctx.isActive = false
        ctx.frameNotifyQueued = false
        ctx.stateLock.unlock()

        if activeTexturesForView[ctx.viewId] == textureId {
          print(
            "[Ladybird][macOS] clearing frame callback for active view=\(ctx.viewId) textureId=\(textureId)"
          )
          set_frame_callback(ctx.viewId, nil, nil)
          activeTexturesForView.removeValue(forKey: ctx.viewId)
        } else {
          let active = activeTexturesForView[ctx.viewId] ?? -1
          print(
            "[Ladybird][macOS] keeping frame callback view=\(ctx.viewId) removedTexture=\(textureId) activeTexture=\(active)"
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
