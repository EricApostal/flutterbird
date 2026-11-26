/// Firefox-style developer tools for the Ladybird engine, speaking the
/// Mozilla remote debugging protocol.
///
/// A browser provides a [DevToolsHost], keeps one [DevToolsManager], and wraps
/// each tab's page in a [DevToolsDockLayout].
library;

export 'src/model/session.dart';
export 'src/model/settings.dart';
export 'src/protocol/devtools_connection.dart';
export 'src/protocol/rdp_client.dart' show RdpError;
export 'src/toolbox/dock.dart';
export 'src/toolbox/manager.dart';
export 'src/toolbox/theme_scope.dart';
export 'src/toolbox/toolbox.dart';
export 'src/toolbox/tools.dart';
