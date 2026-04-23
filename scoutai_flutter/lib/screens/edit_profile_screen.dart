import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../app/scoutai_app.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Edit Profile screen — lets the user update display name, position, nation.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;
  String? _token;
  Uint8List? _medicalDiplomaBytes;
  Uint8List? _bulletinN3Bytes;
  Uint8List? _playerIdDocBytes;
  Uint8List? _medicalDiplomaFileBytes;
  Uint8List? _bulletinN3FileBytes;
  Uint8List? _playerIdDocFileBytes;
  bool _medicalDiplomaHasFile = false;
  bool _bulletinN3HasFile = false;
  bool _playerIdDocHasFile = false;
  String _medicalDiplomaFileName = '';
  String _bulletinN3FileName = '';
  String _playerIdDocFileName = '';
  String _medicalDiplomaContentType = '';
  String _bulletinN3ContentType = '';
  String _playerIdDocContentType = '';
  bool _medicalDiplomaLoading = false;
  bool _bulletinN3Loading = false;
  bool _playerIdDocLoading = false;
  bool _medicalDiplomaUploading = false;
  bool _bulletinN3Uploading = false;
  bool _playerIdDocUploading = false;

  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _nationCtrl = TextEditingController();
  final _playerIdNumberCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _positionCtrl.dispose();
    _nationCtrl.dispose();
    _playerIdNumberCtrl.dispose();
    super.dispose();
  }

  MediaType _mediaTypeForFilename(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.png')) return MediaType('image', 'png');
    if (name.endsWith('.webp')) return MediaType('image', 'webp');
    if (name.endsWith('.gif')) return MediaType('image', 'gif');
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return MediaType('image', 'jpeg');
    if (name.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (name.endsWith('.doc')) return MediaType('application', 'msword');
    if (name.endsWith('.docx')) {
      return MediaType('application', 'vnd.openxmlformats-officedocument.wordprocessingml.document');
    }
    return MediaType('image', 'jpeg');
  }

  String _extractFileName(String? contentDisposition, String fallback) {
    final cd = (contentDisposition ?? '').trim();
    if (cd.isEmpty) return fallback;
    final re = RegExp(r'filename="?([^";]+)"?', caseSensitive: false);
    final m = re.firstMatch(cd);
    if (m == null) return fallback;
    final raw = m.group(1) ?? fallback;
    return Uri.decodeComponent(raw);
  }

  bool _isSupportedImageFilename(String filename) {
    final name = filename.toLowerCase();
    return name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.pdf') ||
        name.endsWith('.doc') ||
        name.endsWith('.docx');
  }

  String _extensionForContentType(String contentType) {
    final ct = contentType.toLowerCase();
    if (ct.contains('image/png')) return '.png';
    if (ct.contains('image/jpeg')) return '.jpg';
    if (ct.contains('image/webp')) return '.webp';
    if (ct.contains('image/gif')) return '.gif';
    if (ct.contains('application/pdf')) return '.pdf';
    if (ct.contains('application/msword')) return '.doc';
    if (ct.contains('application/vnd.openxmlformats-officedocument.wordprocessingml.document')) {
      return '.docx';
    }
    return '';
  }

  String _ensureFileNameWithExtension(String fileName, String contentType, String fallbackBase) {
    final base = fileName.trim().isEmpty ? fallbackBase : fileName.trim();
    final lower = base.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx')) {
      return base;
    }
    final ext = _extensionForContentType(contentType);
    return ext.isEmpty ? base : '$base$ext';
  }

  Future<void> _openOrShareDocument({
    required Uint8List? bytes,
    required String fileName,
    required String contentType,
    required String label,
  }) async {
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      setState(() => _error = '$label is not available yet. Please refresh and try again.');
      return;
    }
    try {
      final resolvedName = _ensureFileNameWithExtension(fileName, contentType, label.toLowerCase().replaceAll(' ', '-'));
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          name: resolvedName,
          mimeType: contentType.isEmpty ? null : contentType,
        ),
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final token = await AuthStorage.loadToken();
    if (!mounted || token == null) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode >= 400) throw Exception('Failed to load profile');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _token = token;
        _nameCtrl.text = (data['displayName'] ?? '').toString();
        _positionCtrl.text = (data['position'] ?? '').toString();
        _nationCtrl.text = (data['nation'] ?? '').toString();
        _playerIdNumberCtrl.text = (data['playerIdNumber'] ?? '').toString();
        _loading = false;
      });
      await _loadMedicalDiploma();
      await _loadBulletinN3();
      await _loadPlayerIdDoc();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _loadMedicalDiploma() async {
    final token = _token;
    if (token == null) return;
    setState(() => _medicalDiplomaLoading = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/player-documents/medical-diploma?ts=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty) {
        setState(() {
          _medicalDiplomaBytes = null;
          _medicalDiplomaFileBytes = null;
          _medicalDiplomaHasFile = false;
          _medicalDiplomaFileName = '';
          _medicalDiplomaContentType = '';
          _medicalDiplomaLoading = false;
        });
        return;
      }
      setState(() {
        _medicalDiplomaFileBytes = res.bodyBytes;
        _medicalDiplomaBytes = ct.startsWith('image/') ? res.bodyBytes : null;
        _medicalDiplomaHasFile = true;
        _medicalDiplomaFileName = _ensureFileNameWithExtension(
          _extractFileName(res.headers['content-disposition'], 'medical-diploma'),
          ct,
          'medical-diploma',
        );
        _medicalDiplomaContentType = ct;
        _medicalDiplomaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _medicalDiplomaBytes = null;
        _medicalDiplomaFileBytes = null;
        _medicalDiplomaHasFile = false;
        _medicalDiplomaFileName = '';
        _medicalDiplomaContentType = '';
        _medicalDiplomaLoading = false;
      });
    }
  }

  Future<void> _loadBulletinN3() async {
    final token = _token;
    if (token == null) return;
    setState(() => _bulletinN3Loading = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/player-documents/bulletin-n3?ts=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty) {
        setState(() {
          _bulletinN3Bytes = null;
          _bulletinN3FileBytes = null;
          _bulletinN3HasFile = false;
          _bulletinN3FileName = '';
          _bulletinN3ContentType = '';
          _bulletinN3Loading = false;
        });
        return;
      }
      setState(() {
        _bulletinN3FileBytes = res.bodyBytes;
        _bulletinN3Bytes = ct.startsWith('image/') ? res.bodyBytes : null;
        _bulletinN3HasFile = true;
        _bulletinN3FileName = _ensureFileNameWithExtension(
          _extractFileName(res.headers['content-disposition'], 'bulletin-n3'),
          ct,
          'bulletin-n3',
        );
        _bulletinN3ContentType = ct;
        _bulletinN3Loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bulletinN3Bytes = null;
        _bulletinN3FileBytes = null;
        _bulletinN3HasFile = false;
        _bulletinN3FileName = '';
        _bulletinN3ContentType = '';
        _bulletinN3Loading = false;
      });
    }
  }

  Future<void> _loadPlayerIdDoc() async {
    final token = _token;
    if (token == null) return;
    setState(() => _playerIdDocLoading = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/player-documents/player-id?ts=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty) {
        setState(() {
          _playerIdDocBytes = null;
          _playerIdDocFileBytes = null;
          _playerIdDocHasFile = false;
          _playerIdDocFileName = '';
          _playerIdDocContentType = '';
          _playerIdDocLoading = false;
        });
        return;
      }
      setState(() {
        _playerIdDocFileBytes = res.bodyBytes;
        _playerIdDocBytes = ct.startsWith('image/') ? res.bodyBytes : null;
        _playerIdDocHasFile = true;
        _playerIdDocFileName = _ensureFileNameWithExtension(
          _extractFileName(res.headers['content-disposition'], 'player-id'),
          ct,
          'player-id',
        );
        _playerIdDocContentType = ct;
        _playerIdDocLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _playerIdDocBytes = null;
        _playerIdDocFileBytes = null;
        _playerIdDocHasFile = false;
        _playerIdDocFileName = '';
        _playerIdDocContentType = '';
        _playerIdDocLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadMedicalDiploma() async {
    final token = _token;
    if (token == null) return;
    setState(() { _medicalDiplomaUploading = true; _error = null; _success = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'pdf', 'doc', 'docx'],
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _medicalDiplomaUploading = false);
        return;
      }
      final file = result.files.first;
      if (!_isSupportedImageFilename(file.name)) {
        setState(() { _medicalDiplomaUploading = false; _error = 'Unsupported image format'; });
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('Failed to read document');

      final uri = Uri.parse('${ApiConfig.baseUrl}/me/player-documents/medical-diploma');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
        contentType: _mediaTypeForFilename(file.name),
      ));
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        setState(() { _medicalDiplomaUploading = false; _error = 'Medical diploma upload failed (${res.statusCode})'; });
        return;
      }
      setState(() {
        _medicalDiplomaUploading = false;
        _medicalDiplomaHasFile = true;
        _medicalDiplomaFileName = file.name;
        _success = 'Medical diploma uploaded';
      });
      await _loadMedicalDiploma();
    } catch (e) {
      if (!mounted) return;
      setState(() { _medicalDiplomaUploading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _pickAndUploadBulletinN3() async {
    final token = _token;
    if (token == null) return;
    setState(() { _bulletinN3Uploading = true; _error = null; _success = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'pdf', 'doc', 'docx'],
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _bulletinN3Uploading = false);
        return;
      }
      final file = result.files.first;
      if (!_isSupportedImageFilename(file.name)) {
        setState(() { _bulletinN3Uploading = false; _error = 'Unsupported image format'; });
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('Failed to read document');

      final uri = Uri.parse('${ApiConfig.baseUrl}/me/player-documents/bulletin-n3');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
        contentType: _mediaTypeForFilename(file.name),
      ));
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        setState(() { _bulletinN3Uploading = false; _error = 'Bulletin n3 upload failed (${res.statusCode})'; });
        return;
      }
      setState(() {
        _bulletinN3Uploading = false;
        _bulletinN3HasFile = true;
        _bulletinN3FileName = file.name;
        _success = 'Bulletin n3 uploaded';
      });
      await _loadBulletinN3();
    } catch (e) {
      if (!mounted) return;
      setState(() { _bulletinN3Uploading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _pickAndUploadPlayerIdDoc() async {
    final token = _token;
    if (token == null) return;
    setState(() { _playerIdDocUploading = true; _error = null; _success = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'pdf', 'doc', 'docx'],
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _playerIdDocUploading = false);
        return;
      }
      final file = result.files.first;
      if (!_isSupportedImageFilename(file.name)) {
        setState(() { _playerIdDocUploading = false; _error = 'Unsupported image format'; });
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('Failed to read document');

      final uri = Uri.parse('${ApiConfig.baseUrl}/me/player-documents/player-id');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
        contentType: _mediaTypeForFilename(file.name),
      ));
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        setState(() { _playerIdDocUploading = false; _error = 'Player ID document upload failed (${res.statusCode})'; });
        return;
      }
      setState(() {
        _playerIdDocUploading = false;
        _playerIdDocHasFile = true;
        _playerIdDocFileName = file.name;
        _success = 'Player ID document uploaded';
      });
      await _loadPlayerIdDoc();
    } catch (e) {
      if (!mounted) return;
      setState(() { _playerIdDocUploading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _save() async {
    final token = _token;
    if (token == null) return;
    setState(() { _saving = true; _error = null; _success = null; });
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me');
      final body = jsonEncode({
        'displayName': _nameCtrl.text.trim(),
        'position': _positionCtrl.text.trim(),
        'nation': _nationCtrl.text.trim(),
        'playerIdNumber': _playerIdNumberCtrl.text.trim(),
      });
      final res = await http.patch(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }, body: body);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        throw Exception('Save failed (${res.statusCode})');
      }
      setState(() { _saving = false; _success = S.current.saved; });

      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Profile saved'),
          content: const Text('Do you want to stay on this page or go to home page?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('stay'),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('home'),
              child: const Text('Home page'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (choice == 'home') {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.playerHome, (_) => false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GradientScaffold(
      appBar: AppBar(
        title: Text(s.editProfile),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Text(s.displayName, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline),
                    hintText: s.fullName,
                  ),
                ),
                const SizedBox(height: 18),
                Text(s.position, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _positionCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.sports_soccer_outlined),
                    hintText: 'ST, CM, GK...',
                  ),
                ),
                const SizedBox(height: 18),
                Text(s.nation, style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nationCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.flag_outlined),
                    hintText: 'TN, FR, US...',
                  ),
                ),
                const SizedBox(height: 18),
                Text('Government ID Number', style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _playerIdNumberCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.badge_outlined),
                    hintText: 'Passport/National ID',
                  ),
                ),
                const SizedBox(height: 24),
                Text('Required documents', style: TextStyle(color: AppColors.txMuted(context), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Medical Diploma', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (_medicalDiplomaLoading || _medicalDiplomaUploading)
                        const SizedBox(height: 36, child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))))
                      else if (_medicalDiplomaBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_medicalDiplomaBytes!, height: 140, width: double.infinity, fit: BoxFit.cover),
                        )
                      else if (_medicalDiplomaHasFile)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.bdr(context)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_medicalDiplomaFileName, style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        )
                      else
                        const Text('Not uploaded', style: TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _medicalDiplomaUploading ? null : _pickAndUploadMedicalDiploma,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_medicalDiplomaBytes != null ? 'Replace Medical Diploma' : 'Upload Medical Diploma'),
                      ),
                      if (_medicalDiplomaHasFile && !_medicalDiplomaUploading && !_medicalDiplomaLoading) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openOrShareDocument(
                            bytes: _medicalDiplomaFileBytes,
                            fileName: _medicalDiplomaFileName,
                            contentType: _medicalDiplomaContentType,
                            label: 'Medical Diploma',
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open / Share Medical Diploma'),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Text('Bulletin n3', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (_bulletinN3Loading || _bulletinN3Uploading)
                        const SizedBox(height: 36, child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))))
                      else if (_bulletinN3Bytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_bulletinN3Bytes!, height: 140, width: double.infinity, fit: BoxFit.cover),
                        )
                      else if (_bulletinN3HasFile)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.bdr(context)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_bulletinN3FileName, style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        )
                      else
                        const Text('Not uploaded', style: TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _bulletinN3Uploading ? null : _pickAndUploadBulletinN3,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_bulletinN3Bytes != null ? 'Replace Bulletin n3' : 'Upload Bulletin n3'),
                      ),
                      if (_bulletinN3HasFile && !_bulletinN3Uploading && !_bulletinN3Loading) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openOrShareDocument(
                            bytes: _bulletinN3FileBytes,
                            fileName: _bulletinN3FileName,
                            contentType: _bulletinN3ContentType,
                            label: 'Bulletin n3',
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open / Share Bulletin n3'),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Text('Player ID Document', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (_playerIdDocLoading || _playerIdDocUploading)
                        const SizedBox(height: 36, child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))))
                      else if (_playerIdDocBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_playerIdDocBytes!, height: 140, width: double.infinity, fit: BoxFit.cover),
                        )
                      else if (_playerIdDocHasFile)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.bdr(context)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_playerIdDocFileName, style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        )
                      else
                        const Text('Not uploaded', style: TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _playerIdDocUploading ? null : _pickAndUploadPlayerIdDoc,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_playerIdDocBytes != null ? 'Replace Player ID Document' : 'Upload Player ID Document'),
                      ),
                      if (_playerIdDocHasFile && !_playerIdDocUploading && !_playerIdDocLoading) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openOrShareDocument(
                            bytes: _playerIdDocFileBytes,
                            fileName: _playerIdDocFileName,
                            contentType: _playerIdDocContentType,
                            label: 'Player ID Document',
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open / Share Player ID Document'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                  ),
                if (_success != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_success!, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(s.save),
                ),
              ],
            ),
    );
  }
}
