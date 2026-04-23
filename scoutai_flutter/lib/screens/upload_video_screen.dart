import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';

import '../app/scoutai_app.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/web_video_upload.dart';
import '../theme/app_colors.dart';
import '../services/translations.dart';
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
  WebVideoHandle? _webPicked;
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

    PlatformFile? file;
    if (kIsWeb) {
      final webFile = await pickWebVideo();
      if (!mounted) return;
      if (webFile == null) return;
      _webPicked = webFile;
      file = PlatformFile(name: webFile.name, size: webFile.size);
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: false,
        withReadStream: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;
      file = result.files.first;
    }

    if (!_isSupportedVideoFilename(file.name)) {
      setState(() {
        _picked = null;
        _webPicked = null;
        _error = S.current.unsupportedVideo;
      });
      return;
    }

    setState(() {
      _picked = file;
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
        final webFile = _webPicked;
        if (webFile == null) {
          throw Exception('No selected web video handle. Please reselect the file.');
        }
        final webRes = await uploadWebVideo(
          url: uri.toString(),
          token: token,
          handle: webFile,
        );
        if (!mounted) return;
        if (webRes.statusCode >= 400) {
          final body = webRes.body.trim();
          setState(() {
            _busy = false;
            _error = body.isNotEmpty
                ? 'Upload failed (${webRes.statusCode}): ${body.length > 200 ? body.substring(0, 200) : body}'
                : 'Upload failed (${webRes.statusCode})';
          });
          return;
        }

        Map<String, dynamic> data;
        try {
          final parsed = jsonDecode(webRes.body);
          data = parsed is Map<String, dynamic> ? parsed : <String, dynamic>{'data': parsed};
        } catch (_) {
          data = <String, dynamic>{'raw': webRes.body};
        }

        setState(() {
          _busy = false;
          _uploaded = data;
          _info = S.current.encryptedTransfer;
        });
        return;
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
          final stream = file.readStream;
          if (stream != null) {
            req.files.add(
              http.MultipartFile(
                'file',
                stream,
                file.size,
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
        _info = S.current.encryptedTransfer;
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
    Navigator.of(context).pushNamed(AppRoutes.tagTeammates, arguments: id);
  }

  String _fileSizeLabel(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  Widget _chipTag(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _flowStepChip(
    BuildContext context, {
    required String label,
    required bool active,
    required bool done,
  }) {
    final tone = done
        ? AppColors.success
        : active
            ? AppColors.primary
            : AppColors.txMuted(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: done
            ? AppColors.success.withValues(alpha: 0.16)
            : active
                ? AppColors.primary.withValues(alpha: 0.14)
                : AppColors.surf2(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: tone,
            size: 14,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statePill(BuildContext context, {required String label, required Color tone}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final picked = _picked;
    final uploaded = _uploaded;
    final canUpload = !_busy;
    final canContinue = uploaded != null;
    final hasPicked = picked != null;
    final progressValue = uploaded != null
        ? 1.0
        : _busy
            ? null
            : 0.0;
    final statusLabel = uploaded != null
        ? s.uploadedSuccessfully
        : _busy
            ? s.uploadingVideo
            : s.ready;
    final statusTone = uploaded != null
        ? AppColors.success
        : _busy
            ? AppColors.primary
            : AppColors.txMuted(context);

    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.uploadMatchVideo),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.surf(context).withValues(alpha: 0.95),
                  AppColors.accent.withValues(alpha: 0.08),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
                      ),
                      child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.newMatchAnalysis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28, height: 1.05),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            s.uploadInstructions,
                            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipTag(context, icon: Icons.movie_creation_outlined, label: 'MP4', tone: AppColors.primary),
                    _chipTag(context, icon: Icons.movie_filter_outlined, label: 'MOV', tone: AppColors.primary),
                    _chipTag(context, icon: Icons.video_collection_outlined, label: 'WEBM', tone: AppColors.primary),
                    _chipTag(context, icon: Icons.sd_storage_outlined, label: 'MAX 2GB', tone: AppColors.accent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: AppColors.surf2(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
                      ),
                      child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.selectMatchVideo,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.tapToUpload,
                            style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: canUpload ? _pickVideo : null,
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: Text(s.browseFiles),
                    ),
                    OutlinedButton.icon(
                      onPressed: (!canUpload || picked == null) ? null : _upload,
                      icon: _busy
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_rounded, size: 18),
                      label: Text(_busy ? s.uploadingVideo : s.upload),
                    ),
                  ],
                ),
                if (hasPicked) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surf2(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.bdr(context).withValues(alpha: 0.9)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_outline, color: AppColors.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            picked.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.tx(context),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _fileSizeLabel(picked.size),
                          style: TextStyle(
                            color: AppColors.txMuted(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _flowStepChip(
                context,
                label: 'PICK VIDEO',
                active: true,
                done: hasPicked || _busy || uploaded != null,
              ),
              _flowStepChip(
                context,
                label: 'UPLOAD',
                active: _busy,
                done: uploaded != null,
              ),
              _flowStepChip(
                context,
                label: 'ANALYZE',
                active: uploaded != null,
                done: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            s.currentUpload,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
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
                            picked?.name ?? s.noFileSelected,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 4),
                          Text(
                            picked == null
                                ? s.chooseVideo
                                : _fileSizeLabel(picked.size),
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _statePill(
                      context,
                      label: uploaded != null
                          ? 'READY'
                          : _busy
                              ? 'UPLOADING'
                              : 'IDLE',
                      tone: statusTone,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: progressValue,
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      statusLabel,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    Text(
                      uploaded != null
                          ? '100%'
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
                  Text(
                    s.encryptedTransfer,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GlassCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canContinue ? _continue : null,
                    icon: const Icon(Icons.analytics_outlined, size: 18),
                    label: Text(s.continueToAnalysis),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  s.buttonActivateWhenDone,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.txMuted(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
