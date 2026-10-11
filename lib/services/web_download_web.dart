import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_download_stub.dart' show WebDownloadResult;

Future<WebDownloadResult> downloadBytes(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/json',
}) async {
  final file = web.File(
    [bytes.toJS].toJS,
    fileName,
    web.FilePropertyBag(type: mimeType),
  );
  final shareData = web.ShareData(files: [file].toJS);

  var canShare = false;
  try {
    canShare = web.window.navigator.canShare(shareData);
  } catch (_) {
    // Browsers without Web Share support use the download/open fallback below.
  }
  var shareFailed = false;
  if (canShare) {
    try {
      await web.window.navigator.share(shareData).toDart;
      return WebDownloadResult.completed;
    } catch (error) {
      if (error.toString().contains('AbortError')) {
        return WebDownloadResult.cancelled;
      }
      shareFailed = true;
    }
  }

  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  if (_isIosBrowser) {
    // iOS Safari ignores the `download` attribute. Opening the blob lets the
    // user use Safari's Share sheet to save the JSON to Files.
    final openedWindow =
        shareFailed ? null : web.window.open(url, '_blank');
    if (openedWindow == null) {
      web.window.location.assign(url);
    }
    _revokeUrlLater(url);
    return WebDownloadResult.openedInBrowser;
  }

  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  _revokeUrlLater(url);
  return WebDownloadResult.completed;
}

bool get _isIosBrowser {
  final platform = web.window.navigator.platform;
  return platform == 'iPhone' ||
      platform == 'iPad' ||
      platform == 'iPod' ||
      (platform == 'MacIntel' && web.window.navigator.maxTouchPoints > 1);
}

void _revokeUrlLater(String url) {
  Timer(const Duration(minutes: 5), () => web.URL.revokeObjectURL(url));
}
