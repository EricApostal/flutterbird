import Cocoa
import CoreVideo
import FlutterMacOS

// C symbols from LadybirdEngine.xcframework — declared via @_silgen_name so Swift
// can call them without a module import (CocoaPods doesn't expose vendored xcframework
// modules to the same pod's Swift sources).
@_silgen_name("tick_ladybird")
func tick_ladybird()

@_silgen_name("get_latest_pixel_buffer")
func get_latest_pixel_buffer() -> UnsafeMutableRawPointer?

@_silgen_name("set_frame_callback")
func set_frame_callback(
  _ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void,
  _ context: UnsafeMutableRawPointer?
)

@_silgen_name("resize_window")
func resize_window(_ width: Int32, _ height: Int32)

@_silgen_name("navigate_to")
func navigate_to(_ url: UnsafePointer<CChar>?)

@_silgen_name("set_zoom")
func set_zoom(_ zoom: Double)

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
  var timer: Timer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "libbird", binaryMessenger: registrar.messenger)
    let instance = LibbirdPlugin()
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

      result(textureId)
    case "unregisterTexture":
      guard let registry = textureRegistry else {
        result(FlutterError(code: "UNAVAILABLE", message: "Texture registry is null", details: nil))
        return
      }
      guard let textureId = call.arguments as? Int64 else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected texture ID", details: nil))
        return
      }
      registry.unregisterTexture(textureId)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
