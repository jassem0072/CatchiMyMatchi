import 'package:http/http.dart' as http;

class WebVideoHandle {
  WebVideoHandle({required this.name, required this.size});

  final String name;
  final int size;
}

Future<WebVideoHandle?> pickWebVideo() async {
  return null;
}

Future<http.Response> uploadWebVideo({
  required String url,
  required String token,
  required WebVideoHandle handle,
  void Function(double progress)? onProgress,
}) async {
  throw UnsupportedError('Web upload is only available on web builds.');
}
