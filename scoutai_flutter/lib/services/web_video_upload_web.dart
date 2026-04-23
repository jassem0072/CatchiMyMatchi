// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

class WebVideoHandle {
  WebVideoHandle(this.file);

  final html.File file;

  String get name => file.name;
  int get size => file.size;
}

Future<WebVideoHandle?> pickWebVideo() async {
  final input = html.FileUploadInputElement();
  input.accept = '.mp4,.mov,.webm,video/*';
  input.multiple = false;
  input.click();

  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  return WebVideoHandle(files.first);
}

Future<http.Response> uploadWebVideo({
  required String url,
  required String token,
  required WebVideoHandle handle,
  void Function(double progress)? onProgress,
}) async {
  final req = html.HttpRequest();
  final done = Completer<http.Response>();

  req.open('POST', url);
  req.setRequestHeader('Authorization', 'Bearer $token');

  req.upload.onProgress.listen((event) {
    if (onProgress == null) return;
    final total = event.total ?? 0;
    final loaded = event.loaded ?? 0;
    if (event.lengthComputable == true && total > 0) {
      onProgress(loaded / total);
    }
  });

  req.onLoadEnd.listen((_) {
    final status = req.status ?? 0;
    done.complete(http.Response(req.responseText ?? '', status));
  });

  final form = html.FormData();
  form.appendBlob('file', handle.file, handle.file.name);
  req.send(form);

  return done.future;
}
