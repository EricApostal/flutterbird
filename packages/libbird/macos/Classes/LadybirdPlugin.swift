import Cocoa
import FlutterMacOS

@_silgen_name("get_latest_pixel_buffer")
func get_latest_pixel_buffer() -> UnsafeMutableRawPointer?

@_silgen_name("tick_ladybird")
func tick_ladybird()

@_silgen_name("set_frame_callback")
func set_frame_callback(
  _ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void, _ context: UnsafeMutableRawPointer?
)

class LadybirdTexture: NSObject, FlutterTexture {
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let ptr = get_latest_pixel_buffer() else {
      return nil
    }
    let buffer = Unmanaged<CVPixelBuffer>.fromOpaque(ptr).takeRetainedValue()
    return Unmanaged.passRetained(buffer)
  }
}

class TextureContext {
  let registry: FlutterTextureRegistry
  let textureId: Int64

  init(registry: FlutterTextureRegistry, textureId: Int64) {
    self.registry = registry
    self.textureId = textureId
  }
}

public class LadybirdPlugin: NSObject, FlutterPlugin {
  var textureRegistry: FlutterTextureRegistry?
  var timer: Timer?
  var currentContextPtr: UnsafeMutableRawPointer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ladybird", binaryMessenger: registrar.messenger)
    let instance = LadybirdPlugin()
    instance.textureRegistry = registrar.textures
    registrar.addMethodCallDelegate(instance, channel: channel)

    instance.startLadybirdLoop()
  }

  private func startLadybirdLoop() {
    let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
      tick_ladybird()
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createTexture":

      guard let registry = textureRegistry else {
        result(FlutterError(code: "UNAVAILABLE", message: "Texture registry is null", details: nil))
        return
      }

      let texture = LadybirdTexture()
      let textureId = registry.register(texture)

      let ctx = TextureContext(registry: registry, textureId: textureId)

      if let oldPtr = currentContextPtr {
        Unmanaged<TextureContext>.fromOpaque(oldPtr).release()
      }
      let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()
      currentContextPtr = ctxPtr

      let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { contextPtr in
        guard let contextPtr = contextPtr else { return }
        let ctx = Unmanaged<TextureContext>.fromOpaque(contextPtr).takeUnretainedValue()

        let textureId = ctx.textureId
        let reg = ctx.registry

        DispatchQueue.main.async {
          reg.textureFrameAvailable(textureId)
        }
      }

      set_frame_callback(callback, ctxPtr)

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
      registry.unregisterTexture(num.int64Value)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
