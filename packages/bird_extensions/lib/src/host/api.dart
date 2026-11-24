import '../extension_registry.dart';
import 'extension_host.dart';
import 'extension_transport.dart';

/// An API call fails in a way the extension should see, as a rejected promise.
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => 'ApiException: $message';
}

/// One call from an extension context.
class ApiCall {
  const ApiCall({
    required this.host,
    required this.context,
    required this.extension,
    required this.method,
    required this.args,
  });

  final ExtensionHost host;
  final ExtensionContext context;
  final InstalledExtension extension;
  final String method;
  final List<Object?> args;

  /// The argument at [index], or null when the call did not pass one.
  Object? arg(int index) => index < args.length ? args[index] : null;
}

/// A group of APIs that share a name, such as `storage`.
abstract class ApiNamespace {
  String get name;

  /// The manifest permission an extension needs to use this namespace, or
  /// null when it needs none.
  String? get requiredPermission => null;

  /// Called once, when the host starts, so the API can listen to the browser.
  void attach(ExtensionHost host) {}

  /// Called when the host stops.
  void detach() {}

  /// Runs [call] and returns what the extension receives, which must be
  /// JSON-encodable. Throw [ApiException] to reject the extension's promise.
  Future<Object?> call(ApiCall call);

  /// Called when an extension is removed so that what it stored can go too.
  Future<void> extensionRemoved(InstalledExtension extension) async {}
}

/// An API that wants to know about contexts coming and going, to report
/// what they imply, as webNavigation does for documents.
abstract interface class ContextObserver {
  void contextCreated(ExtensionHost host, ExtensionContext context);

  void contextDestroyed(ExtensionHost host, ExtensionContext context);

  /// A document of [context] reached `DOMContentLoaded` or `load`.
  void documentEvent(ExtensionHost host, ExtensionContext context, String name);
}
