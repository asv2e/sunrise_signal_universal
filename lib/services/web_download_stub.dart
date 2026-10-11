import 'dart:typed_data';

enum WebDownloadResult { completed, cancelled, openedInBrowser }

Future<WebDownloadResult> downloadBytes(Uint8List bytes, String fileName,
    {String mimeType = 'application/json'}) {
  throw UnsupportedError('Browser download is only available on web.');
}
