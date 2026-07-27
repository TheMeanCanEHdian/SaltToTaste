import 'dart:typed_data';

/// A handle to a browser tab opened to receive a built PDF. Non-web platforms
/// have no such thing, so this stub reports [isOpen] false and the caller falls
/// back to the platform share/print sheet. Mirrors `pdf_tab_web.dart`.
class PdfTab {
  const PdfTab();

  /// Whether a real tab was opened (always false off web).
  bool get isOpen => false;

  /// Navigate the tab to the built PDF (no-op off web).
  void showPdf(Uint8List bytes) {}

  /// Close the placeholder tab if one was opened (no-op off web).
  void closeIfOpen() {}
}

/// Opens a blank browser tab, synchronously, so it rides the user's click
/// gesture (pop-up blockers only allow `window.open` from within one). Off web
/// this is a no-op handle. Call this FIRST in the click handler, then build the
/// PDF, then [PdfTab.showPdf].
PdfTab openPdfTab() => const PdfTab();
