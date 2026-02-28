import Cocoa
import FlutterMacOS

@_silgen_name("get_latest_pixel_buffer")
func get_latest_pixel_buffer() -> UnsafeMutableRawPointer?

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

public class LibbirdPlugin: NSObject, FlutterPlugin {
  var textureRegistry: FlutterTextureRegistry?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "libbird", binaryMessenger: registrar.messenger)
    let instance = LibbirdPlugin()
    instance.textureRegistry = registrar.textures
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "createTexture":
      print("creating texture in swift")

      guard let registry = textureRegistry else {
        result(FlutterError(code: "UNAVAILABLE", message: "Texture registry is null", details: nil))
        return
      }
      print("start texture")
      let texture = LadybirdTexture()
      let textureId = registry.register(texture)

      let ctx = TextureContext(registry: registry, textureId: textureId)
      let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

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
      print("set the frame callback")

      result(textureId)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
