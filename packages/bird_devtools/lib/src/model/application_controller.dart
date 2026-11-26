import 'dart:convert';

import '../protocol/json.dart';
import 'tool_controller.dart';

class ServiceWorkerInfo {
  const ServiceWorkerInfo(this.scope, this.scriptUrl, this.state);
  final String scope;
  final String scriptUrl;
  final String state;
}

/// What the page declares about itself as an installable application.
class ApplicationController extends ToolController {
  ApplicationController(super.session);

  bool loading = false;
  bool loaded = false;
  String manifestUrl = '';
  Map<String, Object?>? manifest;
  String manifestError = '';
  List<ServiceWorkerInfo> workers = const [];
  bool _wanted = false;
  String selected = 'workers';

  void activate() {
    _wanted = true;
    if (!loaded && !loading) refresh();
  }

  void select(String section) {
    selected = section;
    changed();
  }

  @override
  void onTargetDestroyed() {
    loaded = false;
    loading = false;
    manifest = null;
    manifestUrl = '';
    manifestError = '';
    workers = const [];
    changed();
  }

  @override
  void onDocumentComplete() {
    if (_wanted) refresh();
  }

  Future<void> refresh() async {
    if (loading || session.target == null) return;
    loading = true;
    changed();
    try {
      // Both answers come later than a script can wait, so they are left where
      // the next one can read them.
      await session.runInPage(
        'const out = { manifestUrl: "", manifest: null, manifestError: "", workers: [], pending: 0 };'
        'window.__birdApplication = out;'
        'const link = document.querySelector("link[rel~=manifest]");'
        'if (link) { out.manifestUrl = link.href; out.pending++;'
        '  fetch(link.href).then(r => { if (!r.ok) throw new Error("HTTP " + r.status); return r.text(); })'
        '    .then(t => out.manifest = t).catch(e => out.manifestError = String(e)).finally(() => out.pending--); }'
        'if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) { out.pending++;'
        '  navigator.serviceWorker.getRegistrations().then(list => { out.workers = list.map(r => { const w = r.active || r.waiting || r.installing;'
        '    return { scope: r.scope, scriptUrl: w ? w.scriptURL : "", state: w ? w.state : "" }; }); })'
        '    .catch(() => {}).finally(() => out.pending--); }'
        'return true;',
      );
      Map<String, Object?>? answer;
      for (var attempt = 0; attempt < 20; attempt++) {
        final value = await session.runInPage(
          'return window.__birdApplication;',
        );
        if (value is Map<String, Object?>) answer = value;
        if (answer == null || answer.integer('pending') == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (isDisposed) return;
      }
      await session.runInPage('delete window.__birdApplication; return true;');
      if (answer != null) {
        manifestUrl = answer.str('manifestUrl');
        manifestError = answer.str('manifestError');
        manifest = null;
        if (answer.strOrNull('manifest') case final text?) {
          try {
            final decoded = jsonDecode(text);
            if (decoded is Map<String, Object?>) manifest = decoded;
          } on FormatException {
            manifestError = 'The manifest is not valid JSON.';
          }
        }
        workers = [
          for (final worker in answer.maps('workers'))
            ServiceWorkerInfo(
              worker.str('scope'),
              worker.str('scriptUrl'),
              worker.str('state'),
            ),
        ];
      }
      loaded = true;
    } catch (_) {
      // The panel shows what it has.
    }
    loading = false;
    changed();
  }
}
