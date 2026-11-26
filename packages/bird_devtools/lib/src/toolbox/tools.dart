import '../ui/icons.dart';

/// One of the toolbox's tools.
class DevToolsTool {
  const DevToolsTool(this.id, this.label, this.glyph, [this.shortcut = '']);
  final String id;
  final String label;
  final DtGlyph glyph;
  final String shortcut;
}

const List<DevToolsTool> devToolsTools = [
  DevToolsTool('inspector', 'Inspector', DtGlyph.inspector, '⌥⌘C'),
  DevToolsTool('console', 'Console', DtGlyph.console, '⌥⌘K'),
  DevToolsTool('debugger', 'Debugger', DtGlyph.debugger, '⌥⌘Z'),
  DevToolsTool('network', 'Network', DtGlyph.network, '⌥⌘E'),
  DevToolsTool('styleeditor', 'Style Editor', DtGlyph.styleEditor, '⇧F7'),
  DevToolsTool('performance', 'Performance', DtGlyph.performance, '⇧F5'),
  DevToolsTool('memory', 'Memory', DtGlyph.memory),
  DevToolsTool('storage', 'Storage', DtGlyph.storage, '⇧F9'),
  DevToolsTool('accessibility', 'Accessibility', DtGlyph.accessibility, '⇧F12'),
  DevToolsTool('application', 'Application', DtGlyph.application),
];

DevToolsTool? devToolsToolById(String id) {
  for (final tool in devToolsTools) {
    if (tool.id == id) return tool;
  }
  return null;
}
