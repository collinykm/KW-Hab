import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'platform.dart';
import 'url_routing.dart';

/// The plugin cancels WebKit's own download on macOS, so we re-fetch the file
/// (with the web view's cookies) into ~/Downloads.
///
/// Phones/tablets: the device's browser downloads it instead (Chrome on
/// Android, Safari on iOS). It saves into the shared Downloads folder (Files
/// on iOS) and shows its own progress, which an app can't do without broad
/// storage access. Facebook's photo and video downloads are signed links, so
/// they work without our cookies.
Future<void> downloadFile(BuildContext context, DownloadStartRequest request) async {
  final messenger = ScaffoldMessenger.of(context);
  final url = request.url;
  if (isMobile) {
    if (url.scheme == 'http' || url.scheme == 'https') {
      await openExternally(url);
      messenger.showSnackBar(
          const SnackBar(content: Text('Downloading in your browser. Look in Downloads when it finishes.')));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text("This file can't be saved on this device.")));
    }
    return;
  }
  try {
    final dir = await getDownloadsDirectory();
    if (dir == null) throw const FileSystemException('No Downloads folder');

    final name = _safeFileName(
      request.suggestedFilename ??
          (url.pathSegments.isNotEmpty ? url.pathSegments.last : 'download'),
    );
    final file = _uniqueFile(dir, name);

    if (url.scheme == 'data') {
      final data = UriData.fromUri(url);
      await file.writeAsBytes(data.contentAsBytes());
    } else if (url.scheme == 'http' || url.scheme == 'https') {
      messenger.showSnackBar(SnackBar(content: Text('Downloading $name…')));
      final client = HttpClient();
      try {
        final req = await client.getUrl(url);
        final cookies = await CookieManager.instance().getCookies(url: url);
        if (cookies.isNotEmpty) {
          req.headers.set(
            HttpHeaders.cookieHeader,
            cookies.map((c) => '${c.name}=${c.value}').join('; '),
          );
        }
        final res = await req.close();
        if (res.statusCode >= 400) {
          throw HttpException('HTTP ${res.statusCode}', uri: url);
        }
        await res.pipe(file.openWrite());
      } finally {
        client.close();
      }
    } else {
      throw UnsupportedError('This type of download (${url.scheme}:) isn\'t supported.');
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved ${file.uri.pathSegments.last} to Downloads'),
        action: SnackBarAction(
          label: 'Show in Finder',
          onPressed: () => Process.run('open', ['-R', file.path]),
        ),
      ),
    );
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
  }
}

String _safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[/\\:\x00-\x1F]'), '_').trim();
  return cleaned.isEmpty ? 'download' : cleaned;
}

File _uniqueFile(Directory dir, String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var candidate = File('${dir.path}/$name');
  var i = 1;
  while (candidate.existsSync()) {
    candidate = File('${dir.path}/$base ($i)$ext');
    i++;
  }
  return candidate;
}
