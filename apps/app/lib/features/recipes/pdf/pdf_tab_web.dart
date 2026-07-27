import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// A handle to a browser tab opened to receive a built PDF. The tab is opened
/// blank (within the click gesture, so pop-up blockers allow it), shows a
/// placeholder while the PDF builds, then is navigated to a blob URL of the
/// bytes — the browser's own PDF viewer, from which the user prints or saves.
/// Mirrors the `pdf_tab_io.dart` stub used off web.
class PdfTab {
  PdfTab(this._window);

  final web.Window? _window;

  /// Whether a real tab was opened. Null means the pop-up was hard-blocked, so
  /// the caller should fall back to a download.
  bool get isOpen => _window != null;

  void showPdf(Uint8List bytes) {
    final window = _window;
    if (window == null) {
      return;
    }
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    // Navigating the already-open tab to the blob URL is not a new pop-up, so
    // it is never blocked. The PDF's own Title metadata drives the tab title
    // and the browser's save-as name. The URL is left un-revoked on purpose:
    // revoking it would break a reload of the viewer, and it is freed when this
    // (opener) tab unloads.
    window.location.href = web.URL.createObjectURL(blob);
  }

  void closeIfOpen() => _window?.close();
}

PdfTab openPdfTab() {
  final window = web.window.open('', '_blank');
  if (window != null) {
    // A minimal placeholder so the tab is not jarringly blank while the PDF
    // builds (navigating to the blob replaces it).
    window.document.write(
      '<!doctype html><meta charset="utf-8"><title>Building recipe PDF…</title>'
      '<body style="margin:0;height:100vh;display:grid;place-items:center;'
      'font:15px/1.5 system-ui,sans-serif;color:#6b625b">Generating PDF…</body>'
          .toJS,
    );
  }
  return PdfTab(window);
}
