import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'dart:typed_data';

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

class UploadVideoScreen extends StatefulWidget {
  const UploadVideoScreen({super.key});

  @override
  State<UploadVideoScreen> createState() => _UploadVideoScreenState();
}

class _UploadVideoScreenState extends State<UploadVideoScreen> {
  String? _token;
  bool _busy = false;
  String? _error;
  String? _info;
  PlatformFile? _picked;
  Uint8List? _pickedBytes; // web
  Map<String, dynamic>? _uploaded;

  MediaType _videoMediaTypeForFilename(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.mov')) return MediaType('video', 'quicktime');
    if (name.endsWith('.mp4')) return MediaType('video', 'mp4');
    if (name.endsWith('.webm')) return MediaType('video', 'webm');
    return MediaType('video', 'mp4');
  }

  bool _isSupportedVideoFilename(String filename) {
    final name = filename.toLowerCase();
    return name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.webm');
  }

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await AuthStorage.loadToken();
    if (!mounted) return;
    if (token == null) {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      return;
    }
    setState(() => _token = token);
  }

  Future<void> _pickVideo() async {
    setState(() {
      _error = null;
      _info = null;
      _uploaded = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: kIsWeb,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (!_isSupportedVideoFilename(file.name)) {
      setState(() {
        _picked = null;
        _pickedBytes = null;
        _error = 'Unsupported video type. Please use MP4/MOV/WebM.';
      });
      return;
    }

    setState(() {
      _picked = file;
      _pickedBytes = file.bytes;
    });
  }

  Future<void> _upload() async {
    final token = _token;
    final file = _picked;
    if (token == null || file == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _uploaded = null;
    });

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/videos');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';

      if (kIsWeb) {
        final bytes = _pickedBytes;
        if (bytes == null || bytes.isEmpty) throw Exception('Failed to read video');
        req.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: file.name,
            contentType: _videoMediaTypeForFilename(file.name),
          ),
        );
      } else {
        final p = file.path;
        if (p == null || p.isEmpty) {
          final bytes = file.bytes;
          if (bytes == null || bytes.isEmpty) throw Exception('Failed to read video');
          req.files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: file.name,
              contentType: _videoMediaTypeForFilename(file.name),
            ),
          );
        } else {
          req.files.add(
            await http.MultipartFile.fromPath(
              'file',
              p,
              filename: file.name,
              contentType: _videoMediaTypeForFilename(file.name),
            ),
          );
        }
      }

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        final body = res.body.trim();
        setState(() {
          _busy = false;
          _error = body.isNotEmpty
              ? 'Upload failed (${res.statusCode}): ${body.length > 200 ? body.substring(0, 200) : body}'
              : 'Upload failed (${res.statusCode})';
        });
        return;
      }

      Map<String, dynamic> data;
      try {
        final parsed = jsonDecode(res.body);
        data = parsed is Map<String, dynamic> ? parsed : <String, dynamic>{'data': parsed};
      } catch (_) {
        data = <String, dynamic>{'raw': res.body};
      }

      setState(() {
        _busy = false;
        _uploaded = data;
        _info = 'Upload complete. You can continue to analysis.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _continue() {
    final id = _uploaded?['_id'];
    Navigator.of(context).pushNamed(AppRoutes.identifyPlayer, arguments: id);
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    final uploaded = _uploaded;
    final canUpload = !_busy;
    final canContinue = uploaded != null;

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Upload Match Video'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const SizedBox(height: 10),
          const Text(
            'New Match Analysis',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload a high-quality MP4 or MOV file for the best\nAI tracking results.',
            style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.9),
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                Container(
                  height: 64,
                  width: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
                  ),
                  child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary, size: 30),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Select Match Video',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap here to upload MP4 or MOV files\nfrom your gallery (Max 2GB)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: canUpload ? _pickVideo : null,
                  child: const Text('Browse Files'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: (!canUpload || picked == null) ? null : _upload,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Upload'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Current Upload',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
                      ),
                      child: const Icon(Icons.videocam, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            picked?.name ?? 'No file selected',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 4),
                          Text(
                            picked == null
                                ? 'Choose a video to upload'
                                : '${((picked.size) / (1024 * 1024)).toStringAsFixed(1)} MB',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (_busy)
                      const Text(
                        '...',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900),
                      )
                    else if (uploaded != null)
                      const Text(
                        '100%',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: uploaded != null
                        ? 1.0
                        : _busy
                            ? null
                            : 0.0,
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      uploaded != null
                          ? 'Uploaded successfully'
                          : _busy
                              ? 'Uploading video...'
                              : 'Ready',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    Text(
                      uploaded != null
                          ? 'done'
                          : _busy
                              ? '...'
                              : '',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                  )
                else if (_info != null)
                  Text(
                    _info!,
                    style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
                  )
                else
                  const Text(
                    'Encrypted transfer active',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: canContinue ? _continue : null,
            child: const Text('Continue to Analysis'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Button will activate once upload is 100% complete',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
