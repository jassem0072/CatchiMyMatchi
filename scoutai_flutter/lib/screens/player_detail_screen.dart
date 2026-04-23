import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/jwt_utils.dart';
import '../services/pdf_download_helper.dart';
import '../services/translations.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/country_picker.dart';
import '../widgets/fifa_card_stats.dart';
import '../widgets/legendary_player_card.dart';
import '../widgets/list_paginator.dart';

/// Detailed view of a player (used by scouters from Marketplace/Following).
class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({super.key});

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  static const int _breakdownPerPage = 4;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _player;
  Map<String, dynamic>? _dashboard;
  bool _subscriptionExpired = false;
  String? _subscriptionMessage;
  bool _isFavorite = false;
  Map<String, dynamic>? _workflow;
  bool _workflowBusy = false;
  Uint8List? _portraitBytes;
  bool _exportingPdf = false;
  int _breakdownPage = 1;
  int _performanceStep = 0;
  double _breakdownSwipeDx = 0;
  bool _breakdownSwipeConsumed = false;
  final PageController _performanceStepperController = PageController();
  final TextEditingController _fixedPriceCtrl = TextEditingController();
  final TextEditingController _clubNameCtrl = TextEditingController();
  final TextEditingController _clubOfficialNameCtrl = TextEditingController();
  final TextEditingController _startDateCtrl = TextEditingController();
  final TextEditingController _endDateCtrl = TextEditingController();
  final TextEditingController _currencyCtrl = TextEditingController(text: 'EUR');
  final TextEditingController _fixedBaseSalaryCtrl = TextEditingController();
  final TextEditingController _signingFeeCtrl = TextEditingController();
  final TextEditingController _marketValueCtrl = TextEditingController();
  final TextEditingController _bonusAppearanceCtrl = TextEditingController();
  final TextEditingController _bonusGoalCtrl = TextEditingController();
  final TextEditingController _bonusTrophyCtrl = TextEditingController();
  final TextEditingController _releaseClauseCtrl = TextEditingController();
  final TextEditingController _terminationCtrl = TextEditingController();
  final TextEditingController _intermediaryCtrl = TextEditingController();
  String _salaryPeriod = 'monthly';
  Uint8List? _scouterSignatureBytes;
  String _scouterSignatureContentType = 'image/png';
  String _scouterSignatureFileName = 'scouter-signature.png';

  @override
  void dispose() {
    _performanceStepperController.dispose();
    _fixedPriceCtrl.dispose();
    _clubNameCtrl.dispose();
    _clubOfficialNameCtrl.dispose();
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    _currencyCtrl.dispose();
    _fixedBaseSalaryCtrl.dispose();
    _signingFeeCtrl.dispose();
    _marketValueCtrl.dispose();
    _bonusAppearanceCtrl.dispose();
    _bonusGoalCtrl.dispose();
    _bonusTrophyCtrl.dispose();
    _releaseClauseCtrl.dispose();
    _terminationCtrl.dispose();
    _intermediaryCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic> && _player == null) {
      _player = args;
      _isFavorite = args['isFavorite'] == true;
      _loadDashboard();
    }
  }

  Future<void> _loadDashboard() async {
    final player = _player;
    if (player == null) return;
    final playerId = (player['_id'] ?? player['id'])?.toString() ?? '';
    if (playerId.isEmpty) {
      setState(() { _loading = false; });
      return;
    }
    final token = await AuthStorage.loadToken();
    if (!mounted || token == null) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/players/$playerId/dashboard');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode >= 400) {
        debugPrint('GET $uri -> ${res.statusCode}');
        if (res.body.isNotEmpty) debugPrint(res.body);
        final apiMessage = _extractApiMessage(res.body);
        if (_isSubscriptionExpiredError(res.statusCode, apiMessage)) {
          if (!mounted) return;
          setState(() {
            _dashboard = null;
            _subscriptionExpired = true;
            _subscriptionMessage = apiMessage;
            _error = null;
            _breakdownPage = 1;
            _loading = false;
          });
          _computeRichStats();
          _loadPortrait(playerId);
          _loadScouterWorkflow(playerId);
          return;
        }
        final details = apiMessage.isNotEmpty ? ': $apiMessage' : '';
        throw Exception('Failed to load player dashboard (HTTP ${res.statusCode})$details');
      }
      final data = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        if (data is Map<String, dynamic>) {
          final loadedPlayer = data['player'];
          if (loadedPlayer is Map) {
            _player = {
              ...?_player,
              ...Map<String, dynamic>.from(loadedPlayer),
            };
          }
        }
        _dashboard = data is Map<String, dynamic> ? data : null;
        _subscriptionExpired = false;
        _subscriptionMessage = null;
        _breakdownPage = 1;
        _loading = false;
      });
      _computeRichStats();
      // Load portrait
      _loadPortrait(playerId);
      _loadScouterWorkflow(playerId);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _loadScouterWorkflow(String playerId) async {
    final token = await AuthStorage.loadToken();
    if (!mounted || token == null) return;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/admin/players/$playerId');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      if (res.statusCode == 403) return;
      if (res.statusCode >= 400) return;
      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return;
      final wfRaw = data['workflow'];
      if (wfRaw is! Map) return;
      final wf = Map<String, dynamic>.from(wfRaw);
      final draftRaw = wf['contractDraft'];
      final draft = draftRaw is Map ? Map<String, dynamic>.from(draftRaw) : <String, dynamic>{};
      setState(() {
        _workflow = wf;
        final fp = (wf['fixedPrice'] as num?)?.toDouble() ?? 0;
        _fixedPriceCtrl.text = fp <= 0 ? '' : fp.toStringAsFixed(fp.truncateToDouble() == fp ? 0 : 2);
        _clubNameCtrl.text = (draft['clubName'] ?? '').toString();
        _clubOfficialNameCtrl.text = (draft['clubOfficialName'] ?? '').toString();
        _startDateCtrl.text = (draft['startDate'] ?? '').toString();
        _endDateCtrl.text = (draft['endDate'] ?? '').toString();
        _currencyCtrl.text = (draft['currency'] ?? 'EUR').toString();
        _salaryPeriod = (draft['salaryPeriod'] == 'weekly') ? 'weekly' : 'monthly';
        _fixedBaseSalaryCtrl.text = _numToText(draft['fixedBaseSalary']);
        _signingFeeCtrl.text = _numToText(draft['signingOnFee']);
        _marketValueCtrl.text = _numToText(draft['marketValue']);
        _bonusAppearanceCtrl.text = _numToText(draft['bonusPerAppearance']);
        _bonusGoalCtrl.text = _numToText(draft['bonusGoalOrCleanSheet']);
        _bonusTrophyCtrl.text = _numToText(draft['bonusTeamTrophy']);
        _releaseClauseCtrl.text = _numToText(draft['releaseClauseAmount']);
        _terminationCtrl.text = (draft['terminationForCauseText'] ?? '').toString();
        _intermediaryCtrl.text = (draft['scouterIntermediaryId'] ?? '').toString();
        final sigB64 = (wf['scouterSignatureImageBase64'] ?? '').toString();
        if (sigB64.isNotEmpty) {
          try {
            _scouterSignatureBytes = base64Decode(sigB64);
            _scouterSignatureContentType = (wf['scouterSignatureImageContentType'] ?? 'image/png').toString();
            _scouterSignatureFileName = (wf['scouterSignatureImageFileName'] ?? 'scouter-signature.png').toString();
          } catch (_) {
            _scouterSignatureBytes = null;
          }
        }
      });
    } catch (_) {
      // Ignore for non-admin/non-scouter contexts.
    }
  }

  Future<void> _updateScouterDecision(String decision) async {
    final playerId = (_player?['_id'] ?? _player?['id'])?.toString() ?? '';
    if (playerId.isEmpty) return;
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;
    setState(() => _workflowBusy = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/admin/players/$playerId/scouter-decision');
      final res = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'decision': decision}),
      );
      if (!mounted) return;
      if (res.statusCode >= 400) {
        final msg = _extractApiMessage(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.isEmpty ? 'Scouter decision failed' : msg)));
        setState(() => _workflowBusy = false);
        return;
      }
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic> && data['workflow'] is Map) {
        setState(() {
          _workflow = Map<String, dynamic>.from(data['workflow'] as Map);
          _workflowBusy = false;
        });
      } else {
        setState(() => _workflowBusy = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _workflowBusy = false);
    }
  }

  Future<void> _requestExpertVerification() async {
    final playerId = (_player?['_id'] ?? _player?['id'])?.toString() ?? '';
    if (playerId.isEmpty) return;
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;

    setState(() => _workflowBusy = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/admin/players/$playerId/request-info-verification');
      final res = await http.post(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;

      if (res.statusCode >= 400) {
        final msg = _extractApiMessage(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.isEmpty ? 'Unable to request verification' : msg)),
        );
        setState(() => _workflowBusy = false);
        return;
      }

      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic> && data['workflow'] is Map) {
        setState(() {
          _workflow = Map<String, dynamic>.from(data['workflow'] as Map);
          _workflowBusy = false;
        });
      } else {
        setState(() => _workflowBusy = false);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification request sent to expert successfully')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _workflowBusy = false);
    }
  }

  Future<void> _updatePreContract({required String status}) async {
    final playerId = (_player?['_id'] ?? _player?['id'])?.toString() ?? '';
    if (playerId.isEmpty) return;
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;
    if (status == 'approved' && _scouterSignatureBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate your unique QR signature before approval')),
      );
      return;
    }
    final fixedPrice = double.tryParse(_fixedPriceCtrl.text.trim()) ?? 0;

    setState(() => _workflowBusy = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/admin/players/$playerId/pre-contract');
      final res = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'fixedPrice': fixedPrice,
          'status': status,
          'clubName': _clubNameCtrl.text.trim(),
          'clubOfficialName': _clubOfficialNameCtrl.text.trim(),
          'startDate': _startDateCtrl.text.trim(),
          'endDate': _endDateCtrl.text.trim(),
          'currency': _currencyCtrl.text.trim().isEmpty ? 'EUR' : _currencyCtrl.text.trim().toUpperCase(),
          'salaryPeriod': _salaryPeriod,
          'fixedBaseSalary': _parseMoney(_fixedBaseSalaryCtrl.text),
          'signingOnFee': _parseMoney(_signingFeeCtrl.text),
          'marketValue': _parseMoney(_marketValueCtrl.text),
          'bonusPerAppearance': _parseMoney(_bonusAppearanceCtrl.text),
          'bonusGoalOrCleanSheet': _parseMoney(_bonusGoalCtrl.text),
          'bonusTeamTrophy': _parseMoney(_bonusTrophyCtrl.text),
          'releaseClauseAmount': _parseMoney(_releaseClauseCtrl.text),
          'terminationForCauseText': _terminationCtrl.text.trim(),
          'scouterIntermediaryId': _intermediaryCtrl.text.trim(),
          'scouterSignNow': status == 'approved',
          'scouterSignatureImageBase64': _scouterSignatureBytes == null ? '' : base64Encode(_scouterSignatureBytes!),
          'scouterSignatureImageContentType': _scouterSignatureContentType,
          'scouterSignatureImageFileName': _scouterSignatureFileName,
        }),
      );
      if (!mounted) return;
      if (res.statusCode >= 400) {
        final msg = _extractApiMessage(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.isEmpty ? 'Pre-contract update failed' : msg)));
        setState(() => _workflowBusy = false);
        return;
      }
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic> && data['workflow'] is Map) {
        final wf = Map<String, dynamic>.from(data['workflow'] as Map);
        final draftRaw = wf['contractDraft'];
        final draft = draftRaw is Map ? Map<String, dynamic>.from(draftRaw) : const <String, dynamic>{};
        setState(() {
          _workflow = wf;
          _intermediaryCtrl.text = (draft['scouterIntermediaryId'] ?? '').toString();
          _workflowBusy = false;
        });
      } else {
        setState(() => _workflowBusy = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _workflowBusy = false);
    }
  }

  String _extractApiMessage(String body) {
    if (body.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String) return message.trim();
      }
    } catch (_) {}
    return body.trim();
  }

  String _numToText(dynamic value) {
    final n = (value is num) ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (n == null || n <= 0) return '';
    return n.truncateToDouble() == n ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  double _parseMoney(String raw) => double.tryParse(raw.trim()) ?? 0;

  Future<String> _scouterSignatureQrValue() async {
    var userId = '';
    var email = '';
    var role = 'scouter';

    final token = await AuthStorage.loadToken();
    if (token != null) {
      final payload = decodeJwtPayload(token);
      userId = (payload['sub'] ?? payload['id'] ?? '').toString().trim();
      email = (payload['email'] ?? '').toString().trim().toLowerCase();
      final fromTokenRole = (payload['role'] ?? '').toString().trim();
      if (fromTokenRole.isNotEmpty) role = fromTokenRole;
    }

    if (userId.isEmpty) {
      userId = _intermediaryCtrl.text.trim();
    }

    final fallbackName = email.contains('@') ? email.split('@').first : 'scouter';
    final nameParts = fallbackName.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    final pictureRef = (_player?['portraitFile'] ?? '').toString();

    final qrPayload = <String, dynamic>{
      't': 'scoutai-signature',
      'v': 2,
      'role': role,
      'id': userId,
      'nom': lastName.isNotEmpty ? lastName : fallbackName,
      'prenom': firstName,
      'email': email,
      'picture': _portraitBytes != null ? 'portrait-loaded' : pictureRef,
    };
    return jsonEncode(qrPayload);
  }

  Future<Uint8List?> _buildSignatureQrPng(String value) async {
    try {
      final painter = QrPainter(
        data: value,
        version: QrVersions.auto,
        gapless: true,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
      );
      final imageData = await painter.toImageData(512, format: ui.ImageByteFormat.png);
      return imageData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickScouterSignatureImage() async {
    final signatureValue = await _scouterSignatureQrValue();
    final bytes = await _buildSignatureQrPng(signatureValue);
    if (bytes == null || bytes.isEmpty || !mounted) return;
    if (!mounted) return;
    setState(() {
      _scouterSignatureBytes = bytes;
      _scouterSignatureContentType = 'image/png';
      _scouterSignatureFileName = 'scouter-signature-qr-${signatureValue.hashCode.abs()}.png';
    });
  }

  Future<void> _exportContractPdf() async {
    final workflow = _workflow;
    if (workflow == null) return;
    final draftRaw = workflow['contractDraft'];
    final draft = draftRaw is Map ? Map<String, dynamic>.from(draftRaw) : <String, dynamic>{};
    final fixedPrice = (workflow['fixedPrice'] as num?)?.toDouble() ?? 0;
    final currency = (draft['currency'] ?? 'EUR').toString();
    final doc = pw.Document();
    pw.MemoryImage? scouterSig;
    pw.MemoryImage? playerSig;
    pw.MemoryImage? agencySig;
    try {
      final b64 = (workflow['scouterSignatureImageBase64'] ?? '').toString();
      if (b64.isNotEmpty) scouterSig = pw.MemoryImage(base64Decode(b64));
    } catch (_) {}
    try {
      final b64 = (workflow['playerSignatureImageBase64'] ?? '').toString();
      if (b64.isNotEmpty) playerSig = pw.MemoryImage(base64Decode(b64));
    } catch (_) {}
    final agencyQrPayload = jsonEncode(<String, dynamic>{
      't': 'scoutai-signature',
      'v': 2,
      'role': 'agency',
      'id': 'scoutai',
      'nom': 'Agency',
      'prenom': 'ScoutAI',
      'email': 'legal@scoutai.pro',
      'picture': 'scoutai-logo',
    });
    final agencyQrBytes = await _buildSignatureQrPng(agencyQrPayload);
    if (agencyQrBytes != null && agencyQrBytes.isNotEmpty) {
      agencySig = pw.MemoryImage(agencyQrBytes);
    }

    String txt(dynamic value) {
      final s = (value ?? '').toString().trim();
      return s.isEmpty ? '-' : s;
    }

    pw.Widget sectionTitle(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
    );

    final legalArticles = <String>[
      'SECTION I : CADRE JURIDIQUE ET ENGAGEMENT',
      'Article 1 : Identification des parties. Le contrat precise le club, son affiliation federale, et l identite complete du joueur.',
      'Article 2 : Objet du contrat. Le joueur est engage comme Sportif Professionnel soumis au droit du travail applicable.',
      'Article 3 : Duree du contrat. Les dates de debut et de fin sont obligatoires, avec une limite maximale de 5 ans conforme FIFA.',
      'Article 4 : Homologation. Le contrat devient opposable apres validation par la Ligue competente.',
      'Article 5 : Condition de sante. L echec a la visite medicale essentielle peut rendre le contrat nul.',
      'Article 6 : Autorisation de travail. Pour les joueurs hors UE, la validite depend de l obtention du visa sportif.',
      'SECTION II : OBLIGATIONS SPORTIVES',
      'Article 7 : Prestation de travail. Le joueur doit fournir son meilleur effort en match et a l entrainement.',
      'Article 8 : Entrainements. Presence obligatoire, retards et absences peuvent etre sanctionnes.',
      'Article 9 : Competitions. Le joueur dispute les rencontres pour lesquelles il est selectionne.',
      'Article 10 : Stages de preparation. Participation obligatoire aux stages et deplacements, y compris a l etranger.',
      'Article 11 : Soins et recuperation. Le joueur suit les protocoles medicaux prescrits.',
      'Article 12 : Equipements officiels. Port obligatoire des tenues du club lors des apparitions officielles.',
      'Article 13 : Selection nationale. Le club libere le joueur aux dates FIFA avec obligation de retour dans les delais.',
      'SECTION III : REMUNERATION',
      'Article 14 : Salaire mensuel. Le fixe brut est verse selon la periodicite contractuelle.',
      'Article 15 : Prime de signature. Peut etre remboursable en cas de rupture fautive par le joueur.',
      'Article 16 : Prime de presence. Versement par apparition effective en competition officielle.',
      'Article 17 : Prime de victoire ou nul. Bareme collectif annexe au contrat.',
      'Article 18 : Bonus de buts et passes. Paliers de performance definis contractuellement.',
      'Article 19 : Prime d ethique. Bonus conditionne au respect du code de conduite.',
      'Article 20 : Avantages logement. Avantage en nature soumis au regime fiscal applicable.',
      'Article 21 : Vehicule. Mise a disposition eventuelle selon politique club ou sponsor.',
      'Article 22 : Billets d avion. Nombre annuel et conditions de prise en charge definis au contrat.',
      'SECTION IV : DROITS A L IMAGE ET MARKETING',
      'Article 23 : Image collective. Utilisation autorisee dans les campagnes collectives du club.',
      'Article 24 : Image individuelle. Repartition des revenus selon clauses d exploitation individuelle.',
      'Article 25 : Reseaux sociaux. Obligation de moderation, interdiction de propos prejudiciables au club.',
      'Article 26 : Interviews. Soumises a autorisation du service media du club.',
      'Article 27 : Apparitions sponsors. Nombre annuel d obligations promotionnelles fixe contractuellement.',
      'SECTION V : HYGIENE DE VIE ET DISCIPLINE',
      'Article 28 : Etat de forme. Suivi regulier des indicateurs physiques et du poids de forme.',
      'Article 29 : Sports a risque. Pratiques dangereuses interdites sans autorisation ecrite.',
      'Article 30 : Alcool et tabac. Restrictions strictes dans le cadre des activites du club.',
      'Article 31 : Paris sportifs. Interdiction totale de parier sur le football professionnel.',
      'Article 32 : Vie nocturne. Regles de couvre-feu avant competition.',
      'Article 33 : Antidopage. Obligation de se soumettre aux controles inopines.',
      'SECTION VI : PROTECTION ET TRANSFERT',
      'Article 34 : Clause de relegation. Ajustement de remuneration en cas de descente.',
      'Article 35 : Clause liberatoire. Montant fixe permettant un depart sous conditions.',
      'Article 36 : Pourcentage a la revente. Repartition contractuelle sur transfert futur.',
      'Article 37 : Maintien de salaire. Regime applicable en cas de blessure longue duree.',
      'SECTION VII : FIN DE CONTRAT ET LITIGES',
      'Article 38 : Resiliation pour faute grave. Motifs : violence, dopage, corruption, abandon de poste.',
      'Article 39 : Confidentialite. Interdiction de divulgation des termes contractuels a des tiers.',
      'Article 40 : Droit applicable. Litiges soumis aux organes competents FIFA et au TAS selon competence.',
    ];

    final partyLegalNotes = <String>[
      'Player legal obligations: execute sporting duties, respect disciplinary standards, protect confidential information, and comply with medical protocol.',
      'Scouter legal obligations: ensure legal intermediation practice, transparent communication, and proper documentation of negotiation milestones.',
      'ScoutAI Agency legal obligations: provide auditable governance, enforce compliance controls, and apply the 3% agency commission defined by contract.',
      'Joint legal framework: all parties accept digital signature evidence, identity traceability, and dispute handling under the governing law clause.',
    ];

    final playerSigned = workflow['contractSignedByPlayer'] == true;
    final scouterSigned = workflow['scouterSignedContract'] == true;
    final playerSigBox = playerSig == null
        ? pw.Container(height: 120, alignment: pw.Alignment.center, child: pw.Text('Pending signature', style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10)))
        : pw.Container(height: 120, alignment: pw.Alignment.center, child: pw.Image(playerSig, fit: pw.BoxFit.contain));
    final scouterSigBox = scouterSig == null
        ? pw.Container(height: 120, alignment: pw.Alignment.center, child: pw.Text('Pending signature', style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10)))
        : pw.Container(height: 120, alignment: pw.Alignment.center, child: pw.Image(scouterSig, fit: pw.BoxFit.contain));
    final agencySigBox = agencySig == null
      ? pw.Container(height: 120, alignment: pw.Alignment.center, child: pw.Text('Auto-applied QR', style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 10)))
      : pw.Container(height: 120, alignment: pw.Alignment.center, child: pw.Image(agencySig, fit: pw.BoxFit.contain));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey900,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('SCOUTAI PROFESSIONAL PRE-CONTRACT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Text('Digitally prepared contract summary', style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          sectionTitle('Parties'),
          pw.Text(
            'The parties, identity references and contract timeline are expressed below as legal narrative points.',
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.blueGrey700),
          ),
          pw.SizedBox(height: 4),
          pw.Bullet(text: 'Player: ${txt((_player?['displayName'] ?? _player?['email'] ?? 'Unknown'))}'),
          pw.Bullet(text: 'Club: ${txt(draft['clubName'])}'),
          pw.Bullet(text: 'Scouter ID: ${txt(draft['scouterIntermediaryId'])}'),
          pw.Bullet(text: 'Contract period: ${txt(draft['startDate'])} to ${txt(draft['endDate'])}'),
          pw.Bullet(text: 'Salary period: ${txt(draft['salaryPeriod'] ?? _salaryPeriod)}'),
          pw.SizedBox(height: 10),
          sectionTitle('Financial Terms'),
          pw.Text(
            'Compensation terms are detailed with fixed and variable components, plus mandatory platform controls.',
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.blueGrey700),
          ),
          pw.SizedBox(height: 4),
          pw.Bullet(text: 'Fixed transfer contract value: $currency ${fixedPrice.toStringAsFixed(2)}'),
          pw.Bullet(text: 'Fixed base salary: $currency ${_numToText(draft['fixedBaseSalary'])}'),
          pw.Bullet(text: 'Signing fee: $currency ${_numToText(draft['signingOnFee'])}'),
          pw.Bullet(text: 'Market value: $currency ${_numToText(draft['marketValue'])}'),
          pw.Bullet(text: 'Release clause: $currency ${_numToText(draft['releaseClauseAmount'])}'),
          pw.Bullet(text: 'Bonus per appearance: $currency ${_numToText(draft['bonusPerAppearance'])}'),
          pw.Bullet(text: 'Bonus goal/clean sheet: $currency ${_numToText(draft['bonusGoalOrCleanSheet'])}'),
          pw.Bullet(text: 'Bonus team trophy: $currency ${_numToText(draft['bonusTeamTrophy'])}'),
          pw.Bullet(text: 'Platform fee (3%): $currency ${(fixedPrice * 0.03).toStringAsFixed(2)}'),
          pw.Bullet(text: 'ScoutAI agency commission (3%): payable to ScoutAI according to invoicing terms.'),
          pw.Bullet(text: 'Expert verification fee: USD 30 (paid by platform)'),
          pw.SizedBox(height: 10),
          sectionTitle('Termination Clause'),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey200)),
            child: pw.Text(txt(draft['terminationForCauseText'])),
          ),
          pw.SizedBox(height: 12),
          sectionTitle('Cadre Juridique Du Contrat Professionnel'),
          ...legalArticles.map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(c, style: const pw.TextStyle(fontSize: 9.4, lineSpacing: 1.25)),
            ),
          ),
          pw.SizedBox(height: 10),
          sectionTitle('Juridical Responsibilities By Party'),
          ...partyLegalNotes.map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(c, style: const pw.TextStyle(fontSize: 9.4, lineSpacing: 1.25)),
            ),
          ),
          pw.SizedBox(height: 12),
          sectionTitle('Digital Signatures'),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey200)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Player (Left)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      playerSigBox,
                      pw.SizedBox(height: 4),
                      pw.Text('Signed: ${playerSigned ? 'Yes' : 'No'}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Timestamp: ${txt(workflow['contractSignedAt'])}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey200)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Scouter (Right)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      scouterSigBox,
                      pw.SizedBox(height: 4),
                      pw.Text('Signed: ${scouterSigned ? 'Yes' : 'No'}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Timestamp: ${txt(workflow['scouterSignedAt'])}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey200)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('ScoutAI Agency', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      agencySigBox,
                      pw.SizedBox(height: 4),
                      pw.Text('Signed: Yes (Digital QR)', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Timestamp: ${txt(workflow['contractSignedAt'])}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final safeName = ((_player?['displayName'] ?? 'Player').toString()).replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final fileName = 'ScoutAI_Contract_$safeName.pdf';
    final didWebDownload = await triggerPdfDownload(bytes, fileName);
    if (didWebDownload) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contract PDF downloaded: $fileName'), backgroundColor: const Color(0xFF16A34A)),
      );
      return;
    }

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save contract as PDF',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes,
    );
    if (!mounted || savePath == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Contract PDF downloaded: $fileName'), backgroundColor: const Color(0xFF16A34A)),
    );
  }

  bool _isSubscriptionExpiredError(int statusCode, String apiMessage) {
    if (statusCode != 400) return false;
    final normalized = apiMessage.toLowerCase();
    return normalized.contains('subscription expired') ||
        normalized.contains('renew to access player data');
  }

  Widget _moneyField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '${_currencyCtrl.text.trim().isEmpty ? 'EUR' : _currencyCtrl.text.trim().toUpperCase()} ',
        filled: true,
        fillColor: AppColors.surface.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  List<dynamic> _pageSlice(List<dynamic> source, int page, int perPage) {
    final start = (page - 1) * perPage;
    if (start >= source.length) return const [];
    final end = (start + perPage).clamp(0, source.length);
    return source.sublist(start, end);
  }

  Future<void> _loadPortrait(String playerId) async {
    try {
      final token = await AuthStorage.loadToken();
      if (token == null || !mounted) return;
      final pUri = Uri.parse('${ApiConfig.baseUrl}/players/$playerId/portrait');
      final pRes = await http.get(pUri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      final ct = (pRes.headers['content-type'] ?? '').toLowerCase();
      if (pRes.statusCode < 400 && pRes.bodyBytes.isNotEmpty && ct.startsWith('image/')) {
        setState(() => _portraitBytes = pRes.bodyBytes);
      }
    } catch (_) {}
  }

  // Rich stats computed from dashboard videos
  List<Map<String, dynamic>> _perVideo = [];
  Map<String, dynamic> _aggStats = {};
  List<List<double>>? _heatCounts;
  int _heatGridW = 0, _heatGridH = 0;

  FifaCardStats _computeFifaStats(String posLabel) {
    if (_dashboard == null) return FifaCardStats.empty;
    final videos = _dashboard!['videos'] is List ? _dashboard!['videos'] as List : [];
    FifaCardStats? best;
    for (final v in videos) {
      if (v is! Map) continue;
      final a = v['lastAnalysis'];
      if (a is! Map) continue;
      final metrics = a['metrics'] is Map ? Map<String, dynamic>.from(a['metrics'] as Map) : <String, dynamic>{};
      final positions = a['positions'] is List ? a['positions'] as List<dynamic> : <dynamic>[];
      final stats = computeCardStats(metrics, positions, posLabel: posLabel);
      if (best == null || stats.ovr > best.ovr) {
        best = stats;
      }
    }
    return best ?? FifaCardStats.empty;
  }

  void _computeRichStats() {
    if (_dashboard == null) return;
    final videos = _dashboard!['videos'] is List ? _dashboard!['videos'] as List : [];
    double totalDist = 0, maxSpeed = 0, totalAvgSpeed = 0;
    int totalSprints = 0, analyzed = 0, totalAccelPeaks = 0;
    double bestDist = 0, bestAvgSpeed = 0;
    int bestSprints = 0;
    final perVideo = <Map<String, dynamic>>[];
    List<List<double>>? mergedHeat;
    int hW = 0, hH = 0;

    // Movement zones & work rate accumulators
    double sumWalkPct = 0, sumJogPct = 0, sumRunPct = 0, sumHighPct = 0, sumSprintPct = 0;
    int zonesCount = 0;
    double sumWorkRate = 0, sumMovingRatio = 0, sumDirChanges = 0;
    int workRateCount = 0;

    for (final v in videos) {
      if (v is! Map) continue;
      final a = v['lastAnalysis'];
      if (a is! Map) continue;
      analyzed++;
      final metrics = a['metrics'] is Map ? a['metrics'] as Map : a;
      final d = _toDouble(metrics['distanceKm'] ?? metrics['distance_km'] ?? metrics['distanceMeters']);
      final ms = _toDouble(metrics['maxSpeedKmh'] ?? metrics['max_speed_kmh'] ?? metrics['maxSpeed']).clamp(0.0, 45.0);
      final avgS = _toDouble(metrics['avgSpeedKmh'] ?? metrics['avg_speed_kmh'] ?? metrics['avgSpeed']).clamp(0.0, 45.0);
      final sp = _toInt(metrics['sprintCount'] ?? metrics['sprints']);
      final accelList = metrics['accelPeaks'];
      final accelCount = accelList is List ? accelList.length : _toInt(accelList);

      // Heatmap
      final heatmap = metrics['heatmap'];
      if (heatmap is Map) {
        final counts = heatmap['counts'];
        final gw = _toInt(heatmap['grid_w']);
        final gh = _toInt(heatmap['grid_h']);
        if (counts is List && gw > 0 && gh > 0) {
          if (mergedHeat == null || hW != gw || hH != gh) {
            hW = gw; hH = gh;
            mergedHeat ??= List.generate(gh, (_) => List.filled(gw, 0.0));
          }
          for (var r = 0; r < gh && r < counts.length; r++) {
            final row = counts[r];
            if (row is! List) continue;
            for (var c = 0; c < gw && c < row.length; c++) {
              mergedHeat[r][c] += (row[c] is num) ? (row[c] as num).toDouble() : 0.0;
            }
          }
        }
      }

      // Movement analytics extraction
      final movement = metrics['movement'];
      double qualityScore = 0;
      if (movement is Map) {
        final zones = movement['zones'];
        if (zones is Map) {
          sumWalkPct += _toDouble(zones['walking_pct']);
          sumJogPct += _toDouble(zones['jogging_pct']);
          sumRunPct += _toDouble(zones['running_pct']);
          sumHighPct += _toDouble(zones['highSpeed_pct']);
          sumSprintPct += _toDouble(zones['sprinting_pct']);
          zonesCount++;
        }
        final wr = _toDouble(movement['workRateMetersPerMin']);
        final mr = _toDouble(movement['movingRatio']);
        final dc = _toDouble(movement['dirChangesPerMin']);
        if (wr > 0 || mr > 0 || dc > 0) {
          sumWorkRate += wr;
          sumMovingRatio += mr;
          sumDirChanges += dc;
          workRateCount++;
        }
        qualityScore = _toDouble(movement['qualityScore']);
      }

      totalDist += d;
      if (ms > maxSpeed) maxSpeed = ms;
      totalSprints += sp;
      totalAvgSpeed += avgS > 0 ? avgS : ms * 0.6;
      totalAccelPeaks += accelCount;
      if (d > bestDist) bestDist = d;
      if (avgS > bestAvgSpeed) bestAvgSpeed = avgS;
      if (sp > bestSprints) bestSprints = sp;

      perVideo.add({
        'name': (v['originalName'] ?? v['filename'] ?? 'Match $analyzed').toString(),
        'date': (v['createdAt'] ?? v['uploadedAt'] ?? v['date'] ?? '').toString(),
        'videoId': (v['_id'] ?? v['id'])?.toString() ?? '',
        'video': Map<String, dynamic>.from(v),
        'distance': d, 'maxSpeed': ms,
        'avgSpeed': avgS > 0 ? avgS : ms * 0.6,
        'sprints': sp, 'accelPeaks': accelCount,
        'calibrated': (metrics['distanceMeters'] != null && metrics['maxSpeedKmh'] != null),
        'qualityScore': qualityScore,
      });
    }
    _perVideo = perVideo;
    _heatCounts = mergedHeat;
    _heatGridW = hW;
    _heatGridH = hH;
    _aggStats = {
      'totalDistance': totalDist, 'maxSpeed': maxSpeed,
      'avgSpeed': analyzed > 0 ? totalAvgSpeed / analyzed : 0.0,
      'avgDistPerMatch': analyzed > 0 ? totalDist / analyzed : 0.0,
      'totalSprints': totalSprints, 'matchesAnalyzed': analyzed,
      'totalVideos': videos.length, 'totalAccelPeaks': totalAccelPeaks,
      'bestDistance': bestDist, 'bestAvgSpeed': bestAvgSpeed, 'bestSprints': bestSprints,
      'avgWalkPct': zonesCount > 0 ? sumWalkPct / zonesCount : 0.0,
      'avgJogPct': zonesCount > 0 ? sumJogPct / zonesCount : 0.0,
      'avgRunPct': zonesCount > 0 ? sumRunPct / zonesCount : 0.0,
      'avgHighPct': zonesCount > 0 ? sumHighPct / zonesCount : 0.0,
      'avgSprintPct': zonesCount > 0 ? sumSprintPct / zonesCount : 0.0,
      'hasZones': zonesCount > 0,
      'avgWorkRate': workRateCount > 0 ? sumWorkRate / workRateCount : 0.0,
      'avgMovingRatio': workRateCount > 0 ? sumMovingRatio / workRateCount : 0.0,
      'avgDirChanges': workRateCount > 0 ? sumDirChanges / workRateCount : 0.0,
      'hasWorkRate': workRateCount > 0,
    };
  }

  Future<void> _toggleFavorite() async {
    final player = _player;
    if (player == null) return;
    final playerId = (player['_id'] ?? player['id'])?.toString() ?? '';
    if (playerId.isEmpty) return;
    final token = await AuthStorage.loadToken();
    if (token == null) return;
    try {
      if (_isFavorite) {
        await http.delete(
          Uri.parse('${ApiConfig.baseUrl}/favorites/$playerId'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } else {
        await http.post(
          Uri.parse('${ApiConfig.baseUrl}/favorites/$playerId'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite);
    } catch (_) {}
  }

  Map<String, dynamic>? _communicationSummaryFromPlayer(Map<String, dynamic>? player) {
    if (player == null) return null;
    final direct = player['communicationQuiz'];
    if (direct is Map<String, dynamic>) return direct;
    if (direct is Map) return Map<String, dynamic>.from(direct);

    final communication = player['communication'];
    if (communication is Map<String, dynamic>) {
      final summary = communication['summary'];
      if (summary is Map<String, dynamic>) return summary;
      if (summary is Map) return Map<String, dynamic>.from(summary);
    }
    return null;
  }

  String? _pickBestVideoIdForReport() {
    final videos = _dashboard?['videos'];
    if (videos is! List) return null;

    for (final v in videos) {
      if (v is! Map) continue;
      final hasAnalysis = v['lastAnalysis'] is Map;
      final id = (v['_id'] ?? v['id'])?.toString();
      if (hasAnalysis && id != null && id.isNotEmpty) return id;
    }

    for (final v in videos) {
      if (v is! Map) continue;
      final id = (v['_id'] ?? v['id'])?.toString();
      if (id != null && id.isNotEmpty) return id;
    }

    return null;
  }

  Future<bool> _createScouterReport({
    required String title,
    required String notes,
    bool showFeedback = true,
  }) async {
    final player = _player;
    final playerId = (player?['_id'] ?? player?['id'])?.toString() ?? '';
    if (playerId.isEmpty) {
      if (!mounted) return false;
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing player id'), backgroundColor: Color(0xFFEF4444)),
        );
      }
      return false;
    }

    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return false;

    try {
      final videoId = _pickBestVideoIdForReport();
      final stats = _computeFifaStats((player?['position'] ?? 'CM').toString());

      final payload = <String, dynamic>{
        'playerId': playerId,
        'title': title.trim(),
        'notes': notes.trim(),
        'cardSnapshot': {
          'ovr': stats.ovr,
          'pac': stats.pac,
          'sho': stats.sho,
          'pas': stats.pas,
          'dri': stats.dri,
          'def': stats.def,
          'phy': stats.phy,
        },
      };
      if (videoId != null) payload['videoId'] = videoId;

      final uri = Uri.parse('${ApiConfig.baseUrl}/reports');
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 400) {
        final body = res.body;
        throw Exception(body.isNotEmpty ? body : 'Failed to create report');
      }

      if (!mounted) return false;
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report created successfully'), backgroundColor: Color(0xFF16A34A)),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create report: ${e.toString().replaceFirst('Exception: ', '')}'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
      return false;
    }
  }

  Future<void> _downloadPdf() async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      final bytes = await _buildProfessionalPdfBytes();
      final playerName = (_player?['displayName'] ?? _player?['email'] ?? 'Player').toString();
      final safeName = playerName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      final fileName = 'ScoutAI_Report_$safeName.pdf';

      final didWebDownload = await triggerPdfDownload(bytes, fileName);
      if (didWebDownload) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF downloaded: $fileName'), backgroundColor: const Color(0xFF16A34A)),
        );
        return;
      }

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save scouting report as PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );

      if (!mounted) return;
      if (saved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download canceled')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF downloaded: $fileName'), backgroundColor: const Color(0xFF16A34A)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF download error: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<Uint8List> _buildProfessionalPdfBytes() async {
    final player = _player;
    final name = (player?['displayName'] ?? player?['email'] ?? 'Player').toString();
    final position = (player?['position'] ?? 'CM').toString();
    final nation = (player?['nation'] ?? '').toString();
    final email = (player?['email'] ?? '').toString();
    final height = (player?['height'] ?? player?['heightCm'] ?? '').toString();
    final dob = (player?['dateOfBirth'] as String?)?.trim() ?? '';

    int? age;
    if (dob.isNotEmpty) {
      final parsed = DateTime.tryParse(dob);
      if (parsed != null) {
        final now = DateTime.now();
        age = now.year - parsed.year;
        if (now.month < parsed.month || (now.month == parsed.month && now.day < parsed.day)) age--;
      }
    }

    final analyzed = (_aggStats['matchesAnalyzed'] as num? ?? 0).toInt();
    final totalDist = (_aggStats['totalDistance'] as num? ?? 0).toDouble();
    final avgDist = (_aggStats['avgDistPerMatch'] as num? ?? 0).toDouble();
    final topSpeed = (_aggStats['maxSpeed'] as num? ?? 0).toDouble();
    final avgSpeed = (_aggStats['avgSpeed'] as num? ?? 0).toDouble();
    final totalSprints = (_aggStats['totalSprints'] as num? ?? 0).toInt();
    final bestDist = (_aggStats['bestDistance'] as num? ?? 0).toDouble();
    final bestSpeed = (_aggStats['bestAvgSpeed'] as num? ?? 0).toDouble();
    final bestSprints = (_aggStats['bestSprints'] as num? ?? 0).toInt();

    final hasZones = _aggStats['hasZones'] == true;
    final walk = (_aggStats['avgWalkPct'] as num? ?? 0).toDouble();
    final jog = (_aggStats['avgJogPct'] as num? ?? 0).toDouble();
    final run = (_aggStats['avgRunPct'] as num? ?? 0).toDouble();
    final high = (_aggStats['avgHighPct'] as num? ?? 0).toDouble();
    final spr = (_aggStats['avgSprintPct'] as num? ?? 0).toDouble();

    final hasWorkRate = _aggStats['hasWorkRate'] == true;
    final workRate = (_aggStats['avgWorkRate'] as num? ?? 0).toDouble();
    final activity = (_aggStats['avgMovingRatio'] as num? ?? 0).toDouble();
    final dirChanges = (_aggStats['avgDirChanges'] as num? ?? 0).toDouble();

    final fifaStats = _computeFifaStats(position.isNotEmpty ? position : 'CM');
    final mentalReadiness = analyzed > 0 ? ((fifaStats.ovr / 99) * 100).round().clamp(0, 100) : 0;
    final trendRows = _perVideo.take(8).toList();
    final now = DateTime.now();
    String fmt1(double v) => v.toStringAsFixed(1);
    String fmtKm(double meters) => '${(meters / 1000).toStringAsFixed(2)} km';

    final doc = pw.Document();
    final portrait = _portraitBytes != null && _portraitBytes!.isNotEmpty ? pw.MemoryImage(_portraitBytes!) : null;

    pw.Widget title(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
      child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A))),
    );

    pw.Widget paragraph(String text) => pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF334155), lineSpacing: 2),
    );

    pw.Widget infoRow(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(children: [
        pw.SizedBox(width: 110, child: pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF475569)))),
        pw.Expanded(child: pw.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)))),
      ]),
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
        ),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0)))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('SCOUTAI PROFESSIONAL REPORT', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A))),
                pw.Text('Player scouting dossier', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
              ]),
              pw.Text('${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
            ],
          ),
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber}', style: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF64748B))),
        ),
        build: (_) => [
          title('1. Executive Summary'),
          paragraph('This report provides a complete technical overview of the player profile, physical output, movement behavior, and match-by-match performance derived from analyzed video data.'),

          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFC),
              border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 62,
                  height: 62,
                  decoration: pw.BoxDecoration(
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(31)),
                    border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1)),
                  ),
                  child: portrait != null
                      ? pw.ClipRRect(horizontalRadius: 31, verticalRadius: 31, child: pw.Image(portrait, fit: pw.BoxFit.cover))
                      : pw.Center(child: pw.Text(name.isNotEmpty ? name[0].toUpperCase() : 'P')),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text(name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A))),
                    pw.SizedBox(height: 6),
                    infoRow('Position', position),
                    if (nation.isNotEmpty) infoRow('Nationality', nation),
                    if (age != null) infoRow('Age', '$age years'),
                    if (height.isNotEmpty) infoRow('Height', '$height cm'),
                    if (email.isNotEmpty) infoRow('Email', email),
                    infoRow('Overall Rating (OVR)', '${fifaStats.ovr}'),
                  ]),
                ),
              ],
            ),
          ),

          title('2. Performance Overview'),
          paragraph('Key performance indicators aggregate all analyzed matches and summarize physical intensity, distance output, and speed profile.'),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            cellStyle: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF1E293B)),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            headers: const ['Metric', 'Value', 'Interpretation'],
            data: [
              ['Matches analyzed', '$analyzed', 'Volume of validated match data used for this report.'],
              ['Total distance', fmtKm(totalDist), 'Global running load across all analyzed matches.'],
              ['Average distance / match', fmtKm(avgDist), 'Typical physical volume per match.'],
              ['Top speed', '${fmt1(topSpeed)} km/h', 'Peak velocity reached during the analyzed period.'],
              ['Average speed', '${fmt1(avgSpeed)} km/h', 'Sustained movement intensity over match duration.'],
              ['Total sprints', '$totalSprints', 'High-intensity acceleration events counted as sprints.'],
            ],
          ),

          title('3. Technical Profile (FIFA-style attributes)'),
          paragraph('The following scores reflect the best analyzed outputs translated into standardized football attributes.'),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            headers: const ['Attribute', 'Score'],
            data: [
              ['Pace (PAC)', '${fifaStats.pac}'],
              ['Shooting (SHO)', '${fifaStats.sho}'],
              ['Passing (PAS)', '${fifaStats.pas}'],
              ['Dribbling (DRI)', '${fifaStats.dri}'],
              ['Defending (DEF)', '${fifaStats.def}'],
              ['Physical (PHY)', '${fifaStats.phy}'],
            ],
          ),
          paragraph('Radar interpretation: the player profile shows strongest output in pace, passing, and defensive contribution, with balanced dribbling and physical consistency.'),

          title('4. Match Readiness & Speed Trend'),
          paragraph('This section reflects current readiness level and short-term speed trend extracted from recent analyzed matches.'),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            headers: const ['Indicator', 'Value', 'Description'],
            data: [
              ['Mental readiness', '$mentalReadiness%', 'Readiness proxy based on overall rating consistency.'],
              ['Matches in trend window', '${trendRows.length}', 'Recent matches considered for short-term speed trend.'],
              ['Recent avg speed', trendRows.isNotEmpty ? '${fmt1((trendRows.first['avgSpeed'] as num? ?? 0).toDouble())} km/h' : 'No data', 'Most recent analyzed average speed value.'],
              ['Recent top speed', trendRows.isNotEmpty ? '${fmt1((trendRows.first['maxSpeed'] as num? ?? 0).toDouble())} km/h' : 'No data', 'Most recent analyzed maximum speed value.'],
            ],
          ),
          if (trendRows.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
              headers: const ['Match', 'Avg Speed', 'Top Speed'],
              data: trendRows.map((v) {
                final n = (v['name'] ?? 'Match').toString();
                final short = n.length > 30 ? '${n.substring(0, 27)}...' : n;
                return [
                  short,
                  '${fmt1((v['avgSpeed'] as num? ?? 0).toDouble())} km/h',
                  '${fmt1((v['maxSpeed'] as num? ?? 0).toDouble())} km/h',
                ];
              }).toList(),
            ),
          ],

          title('5. Movement and Intensity Analysis'),
          paragraph('Movement zones and workload metrics provide tactical and physiological context to the raw performance figures.'),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            headers: const ['Category', 'Value'],
            data: [
              ['Walking zone', hasZones ? '${fmt1(walk)}%' : 'No data'],
              ['Jogging zone', hasZones ? '${fmt1(jog)}%' : 'No data'],
              ['Running zone', hasZones ? '${fmt1(run)}%' : 'No data'],
              ['High-speed zone', hasZones ? '${fmt1(high)}%' : 'No data'],
              ['Sprinting zone', hasZones ? '${fmt1(spr)}%' : 'No data'],
              ['Work rate', hasWorkRate ? '${fmt1(workRate)} m/min' : 'No data'],
              ['Activity ratio', hasWorkRate ? '${(activity * 100).toStringAsFixed(0)}%' : 'No data'],
              ['Directional changes', hasWorkRate ? '${fmt1(dirChanges)} /min' : 'No data'],
            ],
          ),

          title('6. Tactical Heatmap'),
          paragraph('The tactical heatmap below is generated from the same aggregated positional grid used in the app view.'),
          pw.SizedBox(height: 8),
          _buildPdfHeatmapSection(),

          title('7. Best Match Records'),
          paragraph('Peak single-match outputs captured in the analyzed dataset.'),
          pw.SizedBox(height: 6),
          pw.Bullet(text: 'Best distance: ${fmtKm(bestDist)}'),
          pw.Bullet(text: 'Best average speed: ${fmt1(bestSpeed)} km/h'),
          pw.Bullet(text: 'Best sprints in one match: $bestSprints'),

          title('8. Match-by-Match Breakdown'),
          paragraph('Detailed metrics for each analyzed video entry, including date and core outputs.'),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE2E8F0)),
            cellStyle: const pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF1E293B)),
            headers: const ['#', 'Video', 'Date', 'Dist (m)', 'Top', 'Avg', 'Spr', 'Acc'],
            data: _perVideo.asMap().entries.map((entry) {
              final i = entry.key + 1;
              final v = entry.value;
              final rawName = (v['name'] ?? 'Match $i').toString();
              final date = _formatVideoDate((v['date'] ?? '').toString());
              final shortName = rawName.length > 36 ? '${rawName.substring(0, 33)}...' : rawName;
              return [
                '$i',
                shortName,
                date,
                (v['distance'] as num? ?? 0).toStringAsFixed(0),
                (v['maxSpeed'] as num? ?? 0).toStringAsFixed(1),
                (v['avgSpeed'] as num? ?? 0).toStringAsFixed(1),
                '${v['sprints'] ?? 0}',
                '${v['accelPeaks'] ?? 0}',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildPdfHeatmapSection() {
    if (_heatCounts == null || _heatCounts!.isEmpty || _heatGridW <= 0 || _heatGridH <= 0) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF8FAFC),
          border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Text('No tactical heatmap data available.'),
      );
    }

    final raw = _heatCounts!;
    final srcH = raw.length;
    final srcW = raw.first.length;
    const outW = 36;
    const outH = 24;

    double sampleBilinear(double x, double y) {
      final x0 = x.floor().clamp(0, srcW - 1);
      final y0 = y.floor().clamp(0, srcH - 1);
      final x1 = (x0 + 1).clamp(0, srcW - 1);
      final y1 = (y0 + 1).clamp(0, srcH - 1);
      final dx = (x - x0).clamp(0.0, 1.0);
      final dy = (y - y0).clamp(0.0, 1.0);

      final v00 = raw[y0][x0];
      final v10 = raw[y0][x1];
      final v01 = raw[y1][x0];
      final v11 = raw[y1][x1];

      final top = v00 * (1 - dx) + v10 * dx;
      final bot = v01 * (1 - dx) + v11 * dx;
      return top * (1 - dy) + bot * dy;
    }

    final reduced = List.generate(outH, (_) => List.filled(outW, 0.0));
    for (int r = 0; r < outH; r++) {
      for (int c = 0; c < outW; c++) {
        final sx = (c / (outW - 1)) * (srcW - 1);
        final sy = (r / (outH - 1)) * (srcH - 1);
        reduced[r][c] = sampleBilinear(sx, sy);
      }
    }

    // Light smoothing for a more natural heatmap look in PDF.
    final smoothed = List.generate(outH, (_) => List.filled(outW, 0.0));
    for (int r = 0; r < outH; r++) {
      for (int c = 0; c < outW; c++) {
        double acc = 0;
        int n = 0;
        for (int dr = -1; dr <= 1; dr++) {
          for (int dc = -1; dc <= 1; dc++) {
            final rr = r + dr;
            final cc = c + dc;
            if (rr < 0 || rr >= outH || cc < 0 || cc >= outW) continue;
            acc += reduced[rr][cc];
            n++;
          }
        }
        smoothed[r][c] = n > 0 ? (acc / n) : reduced[r][c];
      }
    }

    double maxVal = 0;
    for (final row in smoothed) {
      for (final v in row) {
        if (v > maxVal) maxVal = v;
      }
    }
    if (maxVal <= 0) maxVal = 1;

    return pw.Container(
      height: 180,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF8FAFC),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Center(
        child: pw.Container(
          width: 540,
          height: 350,
          child: pw.FittedBox(
            fit: pw.BoxFit.contain,
            child: pw.Container(
              width: 108,
              height: 72,
              child: pw.Stack(
                children: [
                  pw.Container(color: const PdfColor.fromInt(0xFF2E7D32)),
                  pw.Column(
                    children: [
                      for (int r = 0; r < outH; r++)
                        pw.Row(
                          children: [
                            for (int c = 0; c < outW; c++)
                              pw.Container(
                                width: 3,
                                height: 3,
                                color: _pdfHeatColor(smoothed[r][c] / maxVal),
                              ),
                          ],
                        ),
                    ],
                  ),
                  // Pitch lines overlay
                  pw.Positioned(left: 1, top: 1, child: pw.Container(width: 106, height: 70, decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xCCFFFFFF), width: 0.6)))),
                  pw.Positioned(left: 54, top: 1, child: pw.Container(width: 0.6, height: 70, color: const PdfColor.fromInt(0xCCFFFFFF))),
                  pw.Positioned(left: 47, top: 29, child: pw.Container(width: 14, height: 14, decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xCCFFFFFF), width: 0.5), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7))))),
                  pw.Positioned(left: 1, top: 22, child: pw.Container(width: 17, height: 28, decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xCCFFFFFF), width: 0.5)))),
                  pw.Positioned(left: 90, top: 22, child: pw.Container(width: 17, height: 28, decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xCCFFFFFF), width: 0.5)))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PdfColor _pdfHeatColor(double t) {
    final v = t.clamp(0.0, 1.0);
    if (v < 0.2) return const PdfColor.fromInt(0xFF4CAF50);
    if (v < 0.4) return const PdfColor.fromInt(0xFF8BC34A);
    if (v < 0.6) return const PdfColor.fromInt(0xFFFFEB3B);
    if (v < 0.8) return const PdfColor.fromInt(0xFFFF9800);
    return const PdfColor.fromInt(0xFFF44336);
  }



  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final dashboardPlayerRaw = _dashboard?['player'];
    final dashboardPlayer = dashboardPlayerRaw is Map
        ? Map<String, dynamic>.from(dashboardPlayerRaw)
        : null;
    final player = dashboardPlayer ?? _player;
    final name = (player?['displayName'] ?? player?['email'] ?? 'Player').toString();
    final position = (player?['position'] ?? '').toString();
    final nation = (player?['nation'] ?? '').toString();
    final fifaStats = _computeFifaStats(position.isNotEmpty ? position : 'CM');
    final analyzed = (_aggStats['matchesAnalyzed'] as int?) ?? 0;
    final topSpeed = (_aggStats['maxSpeed'] as num? ?? 0).toDouble();
    final avgSpeed = (_aggStats['avgSpeed'] as num? ?? 0).toDouble();
    final totalDist = (_aggStats['totalDistance'] as num? ?? 0).toDouble();
    final avgDist = (_aggStats['avgDistPerMatch'] as num? ?? 0).toDouble();
    final totalBreakdownPages = (_perVideo.length / _breakdownPerPage).ceil().clamp(1, 999999);
    final activeBreakdownPage = _breakdownPage.clamp(1, totalBreakdownPages);
    final breakdownSlice = _pageSlice(_perVideo, activeBreakdownPage, _breakdownPerPage);
    final breakdownStartIndex = (activeBreakdownPage - 1) * _breakdownPerPage;
    final readinessPct = analyzed > 0 ? (fifaStats.ovr / 99).clamp(0.0, 1.0) : 0.0;
    final verificationStatus = (_workflow?['verificationStatus'] ?? '').toString();

    return GradientScaffold(
      appBar: AppBar(
        title: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.3),
        ),
        actions: [
          IconButton(
            onPressed: _loading || _workflowBusy ? null : _requestExpertVerification,
            tooltip: verificationStatus == 'pending_expert'
                ? 'Request Expert Verification Again'
                : 'Request Expert Verification',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x1A32D583),
              side: const BorderSide(color: Color(0x5032D583)),
            ),
            icon: Icon(
              verificationStatus == 'pending_expert' ? Icons.notifications_active_rounded : Icons.verified_user_outlined,
              color: const Color(0xFF32D583),
            ),
          ),
          IconButton(
            onPressed: _exportingPdf || _loading ? null : _downloadPdf,
            tooltip: 'Download PDF Report',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x223B82F6),
              side: const BorderSide(color: Color(0x503B82F6)),
            ),
            icon: _exportingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_rounded, color: Colors.white),
          ),
          // ── Challenges button ──
          IconButton(
            onPressed: () => _showChallengesSheet(context),
            tooltip: 'View Challenges',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x22FFD740),
              side: const BorderSide(color: Color(0x55FFD740)),
            ),
            icon: const Icon(Icons.emoji_events_outlined, color: Color(0xFFFFD740)),
          ),
          // ── Follow / Unfollow ──
          IconButton(
            onPressed: _toggleFavorite,
            style: IconButton.styleFrom(
              backgroundColor: _isFavorite
                  ? const Color(0x33FF4D6D)
                  : const Color(0x22FFFFFF),
              side: BorderSide(
                color: _isFavorite
                    ? const Color(0x66FF4D6D)
                    : const Color(0x44FFFFFF),
              ),
            ),
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.redAccent : Colors.white,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loadDashboard,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x883B82F6)),
                            backgroundColor: const Color(0x1A3B82F6),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                          child: Text(
                            S.of(context).retry,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    if (_subscriptionExpired)
                      _card(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFC107)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Subscription required',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (_subscriptionMessage?.isNotEmpty ?? false)
                                        ? _subscriptionMessage!
                                        : 'Subscription expired. Renew to access full player dashboard data.',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).pushNamed('/profile'),
                                    icon: const Icon(Icons.credit_card),
                                    label: const Text('Renew Subscription'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFFFD740),
                                      side: const BorderSide(color: Color(0x88FFD740)),
                                      backgroundColor: const Color(0x1AFFD740),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_subscriptionExpired) const SizedBox(height: 14),

                    // ═══════════ PLAYER CARD ═══════════
                    _staggerItem(
                      order: 0,
                      child: LegendaryPlayerCard(
                        name: name,
                        stats: fifaStats,
                        position: position.isNotEmpty ? position : 'CM',
                        nation: nation,
                        portraitBytes: _portraitBytes,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ═══════════ PLAYER INFO (scouter view) ═══════════
                    _staggerItem(
                      order: 1,
                      child: _PlayerInfoCard(player: player, fifaStats: fifaStats),
                    ),
                    const SizedBox(height: 14),
                    _staggerItem(
                      order: 2,
                      child: _CommunicationResultCard(summary: _communicationSummaryFromPlayer(player)),
                    ),
                    const SizedBox(height: 20),

                    // ═══════════ SWIPE PERFORMANCE STEPPER ═══════════
                    _sectionHeader(Icons.swipe, 'PERFORMANCE STEPPER'),
                    const SizedBox(height: 6),
                    Text(
                      'Swipe left or right to navigate: Performance Score -> Match Readiness -> Player Radar -> Speed Timeline',
                      style: const TextStyle(color: _kTextM, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 340,
                      child: PageView(
                        controller: _performanceStepperController,
                        onPageChanged: (index) => setState(() => _performanceStep = index),
                        children: [
                          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _sectionHeader(Icons.analytics_outlined, 'PERFORMANCE SCORE'),
                            const SizedBox(height: 14),
                            _metricBar('Endurance', (avgDist > 100 ? (avgDist / 12000.0) : (avgDist / 12.0)).clamp(0.0, 1.0)),
                            const SizedBox(height: 8),
                            _metricBar('Top Speed', (topSpeed / 35.0).clamp(0.0, 1.0)),
                            const SizedBox(height: 8),
                            _metricBar('Intensity', ((_aggStats['avgSprintsPerMatch'] as num? ?? 0).toDouble() / 25.0).clamp(0.0, 1.0)),
                            const SizedBox(height: 8),
                            _metricBar('Agility', (((_aggStats['totalAccelPeaks'] as num? ?? 0).toDouble() / (analyzed == 0 ? 1 : analyzed)) / 30.0).clamp(0.0, 1.0)),
                            const SizedBox(height: 8),
                            _metricBar('Work Rate', (((_aggStats['avgWorkRate'] as num? ?? 0).toDouble()) / 150.0).clamp(0.0, 1.0)),
                          ])),
                          _card(child: Column(children: [
                            _sectionHeader(Icons.flash_on, 'MATCH READINESS'),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: _card(child: Column(children: [
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 90, width: 90,
                                  child: CustomPaint(painter: _MentalRingPainter(pct: readinessPct)),
                                ),
                                const SizedBox(height: 8),
                                const Text('MENTAL', style: TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                              ]))),
                              const SizedBox(width: 10),
                              Expanded(child: _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('SPEED TREND', style: TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 80, width: double.infinity,
                                  child: CustomPaint(painter: _MoraleTrendPainter(perVideo: _perVideo)),
                                ),
                              ]))),
                            ]),
                          ])),
                          _card(child: Column(children: [
                            _sectionHeader(Icons.hexagon_outlined, 'PLAYER RADAR'),
                            const SizedBox(height: 10),
                            SizedBox(height: 220, width: 220, child: CustomPaint(painter: _RadarPainter(stats: fifaStats), size: const Size(220, 220))),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                              decoration: BoxDecoration(color: _kAccent, borderRadius: BorderRadius.circular(20)),
                              child: Text('OVR ${fifaStats.ovr}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
                            ),
                          ])),
                          _card(child: Column(children: [
                            _sectionHeader(Icons.speed, 'SPEED TIMELINE'),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 120,
                              width: double.infinity,
                              child: CustomPaint(painter: _MoraleTrendPainter(perVideo: _perVideo)),
                            ),
                            const SizedBox(height: 10),
                            Row(children: [
                              _speedCard(Icons.flash_on, 'Top Speed', '${topSpeed.toStringAsFixed(1)} km/h', _kGreen),
                              const SizedBox(width: 10),
                              _speedCard(Icons.map, 'Total Distance', '${totalDist.toStringAsFixed(1)} m', _kAccent),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              _speedCard(Icons.trending_up, 'Avg Speed', '${avgSpeed.toStringAsFixed(1)} km/h', const Color(0xFFFFA726)),
                              const SizedBox(width: 10),
                              _speedCard(Icons.straighten, 'Avg Dist/Match', '${avgDist.toStringAsFixed(1)} m', _kAccent),
                            ]),
                          ])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        final selected = i == _performanceStep;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: selected ? 18 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: selected ? _kAccent : _kTextM.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),

                    // ═══════════ MOVEMENT ZONES ═══════════
                    Builder(builder: (_) {
                      final hasReal = _aggStats['hasZones'] == true;
                      final walk = hasReal ? (_aggStats['avgWalkPct'] as num? ?? 0).toDouble() : 35.0;
                      final jog  = hasReal ? (_aggStats['avgJogPct']  as num? ?? 0).toDouble() : 28.0;
                      final run  = hasReal ? (_aggStats['avgRunPct']  as num? ?? 0).toDouble() : 20.0;
                      final high = hasReal ? (_aggStats['avgHighPct'] as num? ?? 0).toDouble() : 12.0;
                      final spr  = hasReal ? (_aggStats['avgSprintPct'] as num? ?? 0).toDouble() : 5.0;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _sectionHeader(Icons.directions_run, 'MOVEMENT ZONES'),
                        const SizedBox(height: 10),
                        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              height: 28,
                              child: Row(children: [
                                if (walk > 0) Flexible(flex: (walk * 10).round().clamp(1, 1000), child: Container(color: const Color(0xFF78909C))),
                                if (jog > 0)  Flexible(flex: (jog * 10).round().clamp(1, 1000),  child: Container(color: const Color(0xFF26C6DA))),
                                if (run > 0)  Flexible(flex: (run * 10).round().clamp(1, 1000),  child: Container(color: const Color(0xFF66BB6A))),
                                if (high > 0) Flexible(flex: (high * 10).round().clamp(1, 1000), child: Container(color: const Color(0xFFFFA726))),
                                if (spr > 0)  Flexible(flex: (spr * 10).round().clamp(1, 1000),  child: Container(color: const Color(0xFFEF5350))),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(spacing: 16, runSpacing: 8, children: [
                            _zoneLegend(const Color(0xFF78909C), 'Walk', walk),
                            _zoneLegend(const Color(0xFF26C6DA), 'Jog', jog),
                            _zoneLegend(const Color(0xFF66BB6A), 'Run', run),
                            _zoneLegend(const Color(0xFFFFA726), 'High', high),
                            _zoneLegend(const Color(0xFFEF5350), 'Sprint', spr),
                          ]),
                          if (!hasReal) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: const Color(0x20FFD740), borderRadius: BorderRadius.circular(8)),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.info_outline, size: 13, color: Color(0xFFFFD740)),
                                SizedBox(width: 6),
                                Text('Demo data — calibrate pitch for real zones', style: TextStyle(color: Color(0xFFFFD740), fontSize: 10, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ],
                        ])),
                        const SizedBox(height: 20),
                      ]);
                    }),

                    // ═══════════ WORK RATE & INTENSITY ═══════════
                    Builder(builder: (_) {
                      final hasReal = _aggStats['hasWorkRate'] == true;
                      final wr = hasReal ? (_aggStats['avgWorkRate'] as num? ?? 0).toDouble() : 85.2;
                      final mr = hasReal ? (_aggStats['avgMovingRatio'] as num? ?? 0).toDouble() : 0.72;
                      final dc = hasReal ? (_aggStats['avgDirChanges'] as num? ?? 0).toDouble() : 8.4;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _sectionHeader(Icons.local_fire_department, 'WORK RATE & INTENSITY'),
                        const SizedBox(height: 10),
                        Row(children: [
                          _speedCard(Icons.directions_run, 'Work Rate', '${wr.toStringAsFixed(1)} m/min', const Color(0xFFFF7043)),
                          const SizedBox(width: 10),
                          _speedCard(Icons.directions_walk, 'Activity', '${(mr * 100).toStringAsFixed(0)}%', const Color(0xFF26C6DA)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          _speedCard(Icons.swap_calls, 'Dir. Changes', '${dc.toStringAsFixed(1)} /min', const Color(0xFFAB47BC)),
                          const SizedBox(width: 10),
                          Expanded(child: Container()),
                        ]),
                        if (!hasReal) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: const Color(0x20FFD740), borderRadius: BorderRadius.circular(8)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.info_outline, size: 13, color: Color(0xFFFFD740)),
                              SizedBox(width: 6),
                              Text('Demo data — calibrate pitch for real metrics', style: TextStyle(color: Color(0xFFFFD740), fontSize: 10, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 20),
                      ]);
                    }),

                    // ═══════════ TACTICAL HEATMAP ═══════════
                    _sectionHeader(Icons.grid_on, 'TACTICAL HEATMAP'),
                    const SizedBox(height: 10),
                    _card(child: Column(children: [
                      if (_heatCounts != null && _heatGridW > 0 && _heatGridH > 0)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: _heatGridW / _heatGridH,
                            child: CustomPaint(painter: _HeatmapPainter(counts: _heatCounts!, gridW: _heatGridW, gridH: _heatGridH)),
                          ),
                        )
                      else
                        SizedBox(
                          height: 180, width: double.infinity,
                          child: CustomPaint(painter: _FallbackPitchPainter(position: position.isNotEmpty ? position : 'CM')),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        _heatCounts != null ? 'AGGREGATED FROM $analyzed MATCHES' : 'NO HEATMAP DATA YET',
                        style: const TextStyle(color: _kTextM, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                    ])),
                    const SizedBox(height: 20),

                    // ═══════════ BEST RECORDS ═══════════
                    if (analyzed > 0) ...[
                      _sectionHeader(Icons.emoji_events, 'BEST RECORDS'),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _goldChip('BEST SPEED', '${topSpeed.toStringAsFixed(1)} km/h'),
                          const SizedBox(width: 10),
                          _goldChip('BEST DISTANCE', '${(_aggStats['bestDistance'] as num? ?? 0).toStringAsFixed(0)} m'),
                          const SizedBox(width: 10),
                          _goldChip('BEST SPRINTS', '${_aggStats['bestSprints'] ?? 0} in match'),
                        ]),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ═══════════ MATCH BREAKDOWN ═══════════
                    if (_perVideo.isNotEmpty) ...[
                      _sectionHeader(Icons.table_chart, 'MATCH BREAKDOWN'),
                      const SizedBox(height: 10),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) {
                          _breakdownSwipeDx = 0;
                          _breakdownSwipeConsumed = false;
                        },
                        onHorizontalDragUpdate: (details) {
                          if (_breakdownSwipeConsumed) return;
                          _breakdownSwipeDx += details.primaryDelta ?? 0;
                          if (_breakdownSwipeDx > 30 && activeBreakdownPage < totalBreakdownPages) {
                            setState(() => _breakdownPage = activeBreakdownPage + 1);
                            _breakdownSwipeConsumed = true;
                          } else if (_breakdownSwipeDx < -30 && activeBreakdownPage > 1) {
                            setState(() => _breakdownPage = activeBreakdownPage - 1);
                            _breakdownSwipeConsumed = true;
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          if (_breakdownSwipeConsumed) return;
                          final vx = details.primaryVelocity ?? 0;
                          if (vx > 250 && activeBreakdownPage < totalBreakdownPages) {
                            setState(() => _breakdownPage = activeBreakdownPage + 1);
                          } else if (vx < -250 && activeBreakdownPage > 1) {
                            setState(() => _breakdownPage = activeBreakdownPage - 1);
                          }
                        },
                        child: Column(
                          children: [
                            for (int i = 0; i < breakdownSlice.length; i++) ...[
                              _matchBreakdown(breakdownStartIndex + i + 1, breakdownSlice[i] is Map<String, dynamic> ? breakdownSlice[i] as Map<String, dynamic> : <String, dynamic>{}),
                              const SizedBox(height: 8),
                            ],
                            if (_perVideo.length > _breakdownPerPage) ...[
                              const SizedBox(height: 8),
                              ListPaginator(
                                totalItems: _perVideo.length,
                                itemsPerPage: _breakdownPerPage,
                                currentPage: activeBreakdownPage,
                                onPageChanged: (page) => setState(() => _breakdownPage = page),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Swipe right for next page, swipe left for previous page',
                                style: TextStyle(color: _kTextM, fontSize: 11, fontWeight: FontWeight.w600),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                  ],
                ),
    );
  }

  // ── Dashboard helper builders ──

  static const _kCard = Color(0xFF151B2D);
  static const _kAccent = Color(0xFF2979FF);
  static const _kGreen = Color(0xFF00E676);
  static const _kGold = Color(0xFFFFD740);
  static const _kTextM = Color(0xFF8899AA);

  Widget _staggerItem({required int order, required Widget child}) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 320 + (order * 130)),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      child: child,
      builder: (context, value, widget) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: widget,
          ),
        );
      },
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [
                _kAccent.withValues(alpha: 0.25),
                _kAccent.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(color: _kAccent.withValues(alpha: 0.45)),
          ),
          child: Icon(icon, size: 15, color: _kAccent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              letterSpacing: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kCard,
            Color(0xFF111A2E),
          ],
        ),
        border: Border.all(color: const Color(0x2AFFFFFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _speedCard(IconData icon, String label, String value, Color iconColor) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: iconColor.withValues(alpha: 0.28)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            label,
            style: const TextStyle(
              color: _kTextM,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ])),
      ]),
    ));
  }

  Widget _metricBar(String label, double value) {
    final v = value.clamp(0.0, 1.0);
    final c = v >= 0.75 ? _kGreen : (v >= 0.45 ? _kGold : const Color(0xFFFF6B6B));
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: const TextStyle(color: _kTextM, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(height: 8, decoration: BoxDecoration(color: _kTextM.withValues(alpha: 0.24), borderRadius: BorderRadius.circular(999))),
              FractionallySizedBox(
                widthFactor: v,
                child: Container(height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(999))),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text('${(v * 100).round()}', textAlign: TextAlign.right, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _zoneLegend(Color color, String label, double pct) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 5),
      Text('$label ${pct.toStringAsFixed(1)}%', style: const TextStyle(color: _kTextM, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _goldChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _kCard, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGold.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.emoji_events, size: 14, color: _kGold),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: _kGold, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
        ]),
      ]),
    );
  }

  Widget _matchBreakdown(int index, Map<String, dynamic> data) {
    final name = (data['name'] ?? 'Match $index').toString();
    final dateText = _formatVideoDate((data['date'] ?? '').toString());
    final dist = (data['distance'] as num? ?? 0).toDouble();
    final maxSpd = (data['maxSpeed'] as num? ?? 0).toDouble();
    final avgSpd = (data['avgSpeed'] as num? ?? 0).toDouble();
    final sprints = (data['sprints'] as int?) ?? 0;
    final accel = (data['accelPeaks'] as int?) ?? 0;
    final cal = data['calibrated'] == true;
    final vMap = data['video'] is Map ? Map<String, dynamic>.from(data['video'] as Map) : <String, dynamic>{};

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: vMap.isEmpty
          ? null
          : () => Navigator.of(context).pushNamed('/scouter-video-player', arguments: vMap),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _kAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text('#$index', style: const TextStyle(color: _kAccent, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                  if (dateText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(dateText, style: const TextStyle(color: _kTextM, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            Icon(cal ? Icons.verified : Icons.warning_amber_rounded, color: cal ? _kGreen : _kGold, size: 16),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _miniStat('DIST', '${dist.toStringAsFixed(0)}m', _kAccent),
            _miniStat('TOP', maxSpd.toStringAsFixed(1), _kGreen),
            _miniStat('AVG', avgSpd.toStringAsFixed(1), const Color(0xFFFFA726)),
            _miniStat('SPR', '$sprints', const Color(0xFFEF5350)),
            _miniStat('ACC', '$accel', _kGold),
          ]),
        ]),
      ),
    );
  }

  String _formatVideoDate(String raw) {
    if (raw.trim().isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(child: Column(children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 9, color: color, letterSpacing: 0.5)),
    ]));
  }

  Widget _workflowChip(String label, String value) {
    final normalized = value.toLowerCase();
    final color = normalized.contains('verified') || normalized.contains('approved')
        ? _kGreen
        : normalized.contains('cancel') || normalized.contains('reject')
            ? const Color(0xFFEF5350)
            : _kTextM;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  void _showVideoRequestDialog() {
    final controller = TextEditingController();
    final name = (_player?['displayName'] ?? 'this player').toString();

    showDialog(
      context: context,
      builder: (ctx) {
        bool sending = false;
        bool alsoCreateReport = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surf(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.videocam, color: Color(0xFF8B5CF6), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Request Video from $name',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Describe what kind of video you want. The player will see this in their notifications.',
                    style: TextStyle(color: AppColors.txMuted(context), fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'e.g. "I\'d like to see a video of your dribbling skills in a 1v1 situation, and some free kicks..."',
                      hintStyle: TextStyle(color: AppColors.txMuted(context).withValues(alpha: 0.5), fontSize: 13),
                      fillColor: AppColors.surface.withValues(alpha: 0.7),
                      filled: true,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Quick suggestion chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _quickChip(controller, 'Dribbling skills'),
                      _quickChip(controller, 'Match highlights'),
                      _quickChip(controller, 'Set pieces'),
                      _quickChip(controller, 'Defensive work'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: alsoCreateReport,
                    onChanged: sending
                        ? null
                        : (v) => setDialogState(() => alsoCreateReport = v ?? false),
                    activeColor: const Color(0xFF8B5CF6),
                    title: const Text(
                      'Also create scouting report',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Save this request message into reports for admin/player follow-up.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final msg = controller.text.trim();
                          if (msg.isEmpty) return;
                          setDialogState(() => sending = true);
                          final success = await _sendVideoRequest(msg);
                          bool reportCreated = true;
                          if (alsoCreateReport) {
                            reportCreated = await _createScouterReport(
                              title: 'Video Request Follow-up',
                              notes: msg,
                              showFeedback: false,
                            );
                          }
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          if (success && (!alsoCreateReport || reportCreated)) {
                            final text = alsoCreateReport
                                ? 'Request sent and scouting report created.'
                                : 'Video request sent! The player will see it in their notifications.';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(text),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          } else {
                            final text = !success
                                ? 'Failed to send request. Try again.'
                                : 'Request sent, but report creation failed.';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(text),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                        },
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                  child: sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Send Request'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _quickChip(TextEditingController ctrl, String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () {
        final current = ctrl.text;
        if (current.isNotEmpty && !current.endsWith(' ')) {
          ctrl.text = '$current, ${label.toLowerCase()}';
        } else {
          ctrl.text = '${current}I\'d like to see a video showing your ${label.toLowerCase()}';
        }
        ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
      },
    );
  }

  Future<bool> _sendVideoRequest(String message) async {
    final playerId = (_player?['_id'] ?? _player?['id'])?.toString() ?? '';
    if (playerId.isEmpty) return false;
    try {
      final token = await AuthStorage.loadToken();
      if (token == null) return false;
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/notifications/video-request'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'playerId': playerId, 'message': message}),
      );
      return res.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  void _showChallengesSheet(BuildContext context) {
    final playerId = (_player?['_id'] ?? _player?['id'])?.toString() ?? '';
    final name = (_player?['displayName'] ?? _player?['email'] ?? 'Player').toString();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChallengesSheet(
        playerId: playerId,
        playerName: name,
        onSendVideoRequest: _showVideoRequestDialog,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ══════════════════════════════════════════════════════════════

const _pAccent = Color(0xFF2979FF);
const _pTextM = Color(0xFF8899AA);

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.stats});
  final FifaCardStats stats;
  static const _labels = ['PAC', 'SHO', 'PAS', 'DRI', 'DEF', 'PHY'];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 28;
    final n = _labels.length;
    final step = 2 * math.pi / n;
    final values = [stats.pac, stats.sho, stats.pas, stats.dri, stats.def, stats.phy];
    const gridColor = Color(0x30FFFFFF);
    for (var ring = 1; ring <= 4; ring++) {
      final r = radius * ring / 4;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 2 + i * step;
        final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
        if (i == 0) { path.moveTo(p.dx, p.dy); } else { path.lineTo(p.dx, p.dy); }
      }
      path.close();
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..color = gridColor);
    }
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      canvas.drawLine(center, Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a)),
        Paint()..color = gridColor..strokeWidth = 0.8);
    }
    final dp = Path();
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      final r = radius * (values[i] / 99).clamp(0.0, 1.0);
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      if (i == 0) { dp.moveTo(p.dx, p.dy); } else { dp.lineTo(p.dx, p.dy); }
    }
    dp.close();
    canvas.drawPath(dp, Paint()..style = PaintingStyle.fill..color = _pAccent.withValues(alpha: 0.22));
    canvas.drawPath(dp, Paint()..style = PaintingStyle.stroke..color = _pAccent..strokeWidth = 2.5);
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * step;
      final r = radius * (values[i] / 99).clamp(0.0, 1.0);
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      canvas.drawCircle(p, 4, Paint()..color = _pAccent);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);
      final lo = Offset(center.dx + (radius + 20) * math.cos(a), center.dy + (radius + 20) * math.sin(a));
      final tp = TextPainter(
        text: TextSpan(text: '${_labels[i]}\n${values[i]}',
          style: const TextStyle(color: _pTextM, fontSize: 10, fontWeight: FontWeight.w800, height: 1.3)),
        textAlign: TextAlign.center, textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lo.dx - tp.width / 2, lo.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.stats.ovr != stats.ovr;
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({required this.counts, required this.gridW, required this.gridH});
  final List<List<double>> counts;
  final int gridW, gridH;

  static const _spectrum = [
    Color(0xFF1B8A2F), Color(0xFF2DB84B), Color(0xFF7FD858),
    Color(0xFFCCF03D), Color(0xFFFFFF00), Color(0xFFFFD200),
    Color(0xFFFF9800), Color(0xFFFF5722), Color(0xFFE91E1E),
    Color(0xFFB71C1C), Color(0xFF880E0E),
  ];

  Color _heatColor(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final idx = clamped * (_spectrum.length - 1);
    final lo = idx.floor().clamp(0, _spectrum.length - 2);
    return Color.lerp(_spectrum[lo], _spectrum[lo + 1], idx - lo)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2E7D32));
    final stripeCount = 12;
    for (var i = 1; i < stripeCount; i += 2) {
      canvas.drawRect(Rect.fromLTWH(i * w / stripeCount, 0, w / stripeCount, h), Paint()..color = const Color(0xFF388E3C));
    }

    double maxVal = 0;
    for (final row in counts) { for (final v in row) { if (v > maxVal) maxVal = v; } }
    if (maxVal <= 0) { _drawPitchLines(canvas, w, h); return; }

    final resX = (w / 4).ceil(), resY = (h / 4).ceil();
    final field = List.generate(resY, (_) => List.filled(resX, 0.0));
    final cellW = w / gridW, cellH = h / gridH;
    final sigmaX = cellW * 1.8, sigmaY = cellH * 1.8;

    for (var r = 0; r < gridH && r < counts.length; r++) {
      for (var c = 0; c < gridW && c < counts[r].length; c++) {
        final v = counts[r][c];
        if (v <= 0) continue;
        final norm = v / maxVal;
        final cx = (c + 0.5) * cellW, cy = (r + 0.5) * cellH;
        final fcx = cx / w * resX, fcy = cy / h * resY;
        final fSigX = sigmaX / w * resX, fSigY = sigmaY / h * resY;
        final rx = (fSigX * 3).ceil(), ry = (fSigY * 3).ceil();
        for (var fy = (fcy - ry).floor().clamp(0, resY - 1); fy <= (fcy + ry).ceil().clamp(0, resY - 1); fy++) {
          for (var fx = (fcx - rx).floor().clamp(0, resX - 1); fx <= (fcx + rx).ceil().clamp(0, resX - 1); fx++) {
            final dx = fx - fcx, dy = fy - fcy;
            field[fy][fx] += norm * math.exp(-(dx * dx) / (2 * fSigX * fSigX) - (dy * dy) / (2 * fSigY * fSigY));
          }
        }
      }
    }

    double fieldMax = 0;
    for (final row in field) { for (final v in row) { if (v > fieldMax) fieldMax = v; } }
    if (fieldMax <= 0) fieldMax = 1;

    final pw = w / resX, ph = h / resY;
    for (var fy = 0; fy < resY; fy++) {
      for (var fx = 0; fx < resX; fx++) {
        final t = (field[fy][fx] / fieldMax).clamp(0.0, 1.0);
        if (t < 0.08) continue;
        canvas.drawRect(Rect.fromLTWH(fx * pw, fy * ph, pw + 0.5, ph + 0.5), Paint()..color = _heatColor(t).withValues(alpha: 0.35 + t * 0.55));
      }
    }
    _drawPitchLines(canvas, w, h);
  }

  void _drawPitchLines(Canvas canvas, double w, double h) {
    final lp = Paint()..color = const Color(0xBBFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTWH(3, 3, w - 6, h - 6), lp);
    canvas.drawLine(Offset(w / 2, 3), Offset(w / 2, h - 3), lp);
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.16, lp);
    canvas.drawCircle(Offset(w / 2, h / 2), 3, Paint()..color = const Color(0xBBFFFFFF));
    canvas.drawRect(Rect.fromLTWH(3, h * 0.2, w * 0.17, h * 0.6), lp);
    canvas.drawRect(Rect.fromLTWH(w - 3 - w * 0.17, h * 0.2, w * 0.17, h * 0.6), lp);
    canvas.drawRect(Rect.fromLTWH(3, h * 0.35, w * 0.07, h * 0.3), lp);
    canvas.drawRect(Rect.fromLTWH(w - 3 - w * 0.07, h * 0.35, w * 0.07, h * 0.3), lp);
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) => false;
}

class _MentalRingPainter extends CustomPainter {
  _MentalRingPainter({required this.pct});
  final double pct;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 6;
    canvas.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = const Color(0x20FFFFFF));
    final sweep = 2 * math.pi * pct;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, sweep, false,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round..color = const Color(0xFF00E676));
    final pctText = '${(pct * 100).round()}%';
    final tp = TextPainter(
      text: TextSpan(text: pctText, style: const TextStyle(color: Color(0xFF00E676), fontSize: 22, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MentalRingPainter old) => old.pct != pct;
}

class _MoraleTrendPainter extends CustomPainter {
  _MoraleTrendPainter({required this.perVideo});
  final List<Map<String, dynamic>> perVideo;

  @override
  void paint(Canvas canvas, Size size) {
    final scores = <double>[];
    for (final v in perVideo) {
      final d = (v['distance'] as num? ?? 0).toDouble();
      final s = (v['maxSpeed'] as num? ?? 0).toDouble();
      scores.add((d + s).clamp(0.0, 200.0) / 200.0);
    }
    if (scores.isEmpty) scores.addAll([0.3, 0.5, 0.7]);

    final w = size.width, h = size.height;
    final n = scores.length;
    for (var i = 0; i < 4; i++) {
      final y = h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(w, y), Paint()..color = const Color(0x15FFFFFF));
    }
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : w * i / (n - 1);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: const TextStyle(color: Color(0x60FFFFFF), fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, h - tp.height));
    }
    final path = Path();
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : w * i / (n - 1);
      final y = (h - 14) * (1 - scores[i]) + 2;
      pts.add(Offset(x, y));
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..color = const Color(0xFF00E676)..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
    final fill = Path.from(path)..lineTo(pts.last.dx, h)..lineTo(pts.first.dx, h)..close();
    canvas.drawPath(fill, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0x4000E676), Color(0x0000E676)],
    ).createShader(Rect.fromLTWH(0, 0, w, h)));
    for (final p in pts) {
      canvas.drawCircle(p, 3, Paint()..color = const Color(0xFF00E676));
    }
  }

  @override
  bool shouldRepaint(covariant _MoraleTrendPainter old) => true;
}

class _FallbackPitchPainter extends CustomPainter {
  _FallbackPitchPainter({required this.position});
  final String position;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)), Paint()..color = const Color(0xFF1B5E20));
    canvas.clipRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)));
    final lp = Paint()..color = const Color(0x60FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawRect(Rect.fromLTWH(4, 4, w - 8, h - 8), lp);
    canvas.drawLine(Offset(w / 2, 4), Offset(w / 2, h - 4), lp);
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.18, lp);
    canvas.drawRect(Rect.fromLTWH(4, h * 0.2, w * 0.16, h * 0.6), lp);
    canvas.drawRect(Rect.fromLTWH(w - 4 - w * 0.16, h * 0.2, w * 0.16, h * 0.6), lp);
    final tp = TextPainter(
      text: const TextSpan(text: 'No heatmap data yet', style: TextStyle(color: Color(0x80FFFFFF), fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, h / 2 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _FallbackPitchPainter old) => false;
}

// ══════════════════════════════════════════════════════════════════════════════
// PLAYER INFO CARD (scouter view — age, country, position, OVR, height)
// ══════════════════════════════════════════════════════════════════════════════

class _PlayerInfoCard extends StatelessWidget {
  const _PlayerInfoCard({required this.player, required this.fifaStats});
  final Map<String, dynamic>? player;
  final FifaCardStats fifaStats;

  static const _kCard = Color(0xFF151B2D);
  static const _kGold = Color(0xFFFFD740);

  int _age() {
    final dob = player?['dateOfBirth'] ?? player?['dob'] ?? player?['birthDate'];
    if (dob == null) return -1;
    try {
      final str = dob.toString();
      if (str.isEmpty || str == 'null') return -1;
      final dt = DateTime.parse(str);
      final now = DateTime.now();
      int age = now.year - dt.year;
      if (now.month < dt.month || (now.month == dt.month && now.day < dt.day)) age--;
      return age >= 0 ? age : -1;
    } catch (_) { return -1; }
  }

  int _height() {
    final h = player?['height'] ?? player?['heightCm'];
    if (h == null) return -1;
    if (h is num) return h.round();
    final parsed = double.tryParse(h.toString());
    if (parsed != null) return parsed.round();
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final age = _age();
    final ht = _height();
    final position = (player?['position'] as String?)?.toUpperCase() ?? '';
    final country = (player?['nation'] ?? player?['country'] ?? '').toString();
    final flag = country.isNotEmpty ? flagForCountry(country) : '';
    final isVerified = player?['badgeVerified'] == true;

    // Only show card if there's at least some data
    final hasAny = age >= 0 || ht >= 0 || position.isNotEmpty || country.isNotEmpty || fifaStats.ovr > 0;
    if (!hasAny) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kCard,
            Color(0xFF111B31),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGold.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.lock_outline_rounded, size: 14, color: _kGold),
            const SizedBox(width: 6),
            const Text(
              'PRIVATE INFO',
              style: TextStyle(
                color: _kGold,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.45,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _InfoRow(icon: Icons.cake_outlined, label: 'Age',
              value: age >= 0 ? '$age yrs' : '—', missing: age < 0)),
            const SizedBox(width: 8),
            Expanded(child: _InfoRow(icon: Icons.flag_outlined, label: 'Country',
              value: country.isNotEmpty ? '$flag $country' : '—', missing: country.isEmpty)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _InfoRow(icon: Icons.sports_soccer, label: 'Position',
              value: position.isNotEmpty ? position : '—', missing: position.isEmpty)),
            const SizedBox(width: 8),
            Expanded(child: _InfoRow(
              icon: Icons.star_outline, label: 'Avg Rating',
              value: fifaStats.ovr > 0 ? '${fifaStats.ovr}' : '—',
              missing: false,
              valueColor: fifaStats.ovr >= 80
                  ? const Color(0xFFFFD600)
                  : fifaStats.ovr >= 65 ? const Color(0xFF76FF03) : null,
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _InfoRow(icon: Icons.height, label: 'Height',
              value: ht >= 0 ? '$ht cm' : '—', missing: ht < 0)),
            const SizedBox(width: 8),
            Expanded(
              child: _InfoRow(
                icon: isVerified ? Icons.verified_rounded : Icons.pending_rounded,
                label: 'Verification',
                value: isVerified ? 'Verified' : 'Pending',
                missing: false,
                valueColor: isVerified ? const Color(0xFF00E676) : const Color(0xFFFFB300),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _CommunicationResultCard extends StatelessWidget {
  const _CommunicationResultCard({required this.summary});

  final Map<String, dynamic>? summary;

  static const _kCard = Color(0xFF151B2D);
  static const _kTextM = Color(0xFF9AA3B2);

  @override
  Widget build(BuildContext context) {
    final band = (summary?['readinessBand'] ?? summary?['band'] ?? 'Not available').toString();
    final style = (summary?['communicationStyle'] ?? 'Not available').toString();
    final captaincy = (summary?['captaincy'] ?? summary?['captaincySummary'] ?? 'Not available').toString();
    final languages = summary?['languages'];
    final languageText = languages is List && languages.isNotEmpty
        ? languages.map((e) => e.toString()).join(', ')
        : 'Not available';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kCard,
            Color(0xFF111A2E),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x283B82F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.record_voice_over_outlined, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text(
                'SCOUTER COMMUNICATION VIEW',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(
            'Readiness',
            band,
            valueColor: band.toLowerCase().contains('good')
                ? const Color(0xFF32D583)
                : (band.toLowerCase().contains('not') ? _kTextM : Colors.white),
          ),
          const SizedBox(height: 8),
          _infoRow('Style', style),
          const SizedBox(height: 8),
          _infoRow('Captaincy', captaincy),
          const SizedBox(height: 8),
          _infoRow('Languages', languageText),
          if (summary == null) ...[
            const SizedBox(height: 10),
            const Text(
              'Player has not completed communication quiz yet.',
              style: TextStyle(color: _kTextM, fontSize: 12.5, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 98,
            child: Text(
              label,
              style: const TextStyle(
                color: _kTextM,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon, required this.label,
    required this.value, required this.missing,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool missing;
  final Color? valueColor;

  static const _kAccent = Color(0xFF2979FF);
  static const _kTextM  = Color(0xFF8899AA);

  @override
  Widget build(BuildContext context) {
    final iconColor = missing ? _kTextM : _kAccent;
    final dataColor = missing ? _kTextM : (valueColor ?? Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: missing
              ? _kTextM.withValues(alpha: 0.2)
              : _kAccent.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _kTextM,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.55,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: dataColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontStyle: missing ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CHALLENGES SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _ChallengesSheet extends StatefulWidget {
  const _ChallengesSheet({
    required this.playerId,
    required this.playerName,
    required this.onSendVideoRequest,
  });
  final String playerId;
  final String playerName;
  final VoidCallback onSendVideoRequest;

  @override
  State<_ChallengesSheet> createState() => _ChallengesSheetState();
}

class _ChallengesSheetState extends State<_ChallengesSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _challenges = [];

  static const _kCard  = Color(0xFF151B2D);
  static const _kAccent = Color(0xFF2979FF);
  static const _kGreen = Color(0xFF00E676);
  static const _kTextM = Color(0xFF8899AA);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.playerId.isEmpty) {
      setState(() { _loading = false; _error = 'No player ID'; });
      return;
    }
    try {
      final token = await AuthStorage.loadToken();
      if (token == null || !mounted) return;
      final uri = Uri.parse('${ApiConfig.baseUrl}/players/${widget.playerId}/challenges');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      if (res.statusCode >= 400) {
        setState(() { _loading = false; _error = 'Could not load challenges (HTTP ${res.statusCode})'; });
        return;
      }
      final parsed = jsonDecode(res.body);
      final list = parsed is List
          ? parsed.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[];
      setState(() { _challenges = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Color _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed': return _kGreen;
      case 'in_progress': return _kAccent;
      case 'failed': return const Color(0xFFEF5350);
      default: return _kTextM;
    }
  }

  IconData _statusIcon(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'completed': return Icons.check_circle;
      case 'in_progress': return Icons.timelapse;
      case 'failed': return Icons.cancel;
      default: return Icons.radio_button_unchecked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF151B2D) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? const Color(0xFF2A3550) : Colors.black12;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.emoji_events_outlined, color: Color(0xFFFFD740), size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${widget.playerName}\'s Challenges',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 17),
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: _SheetActionButton(
                  onTap: widget.onSendVideoRequest,
                  icon: Icons.videocam_outlined,
                  label: 'Send Video Request',
                ),
              ),
            ),
            Divider(color: borderColor, height: 24),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: const TextStyle(color: Color(0xFFEF5350))),
                        ))
                      : _challenges.isEmpty
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.emoji_events_outlined, size: 48, color: Color(0xFF8899AA)),
                              const SizedBox(height: 12),
                              Text('No challenges yet', style: TextStyle(color: _kTextM, fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 6),
                              Text('This player hasn\'t completed any challenges.', style: TextStyle(color: _kTextM, fontSize: 13)),
                            ]))
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: _challenges.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final c = _challenges[i];
                                final title = (c['title'] ?? c['name'] ?? c['challengeId'] ?? 'Challenge').toString();
                                final desc = (c['description'] ?? '').toString();
                                final status = (c['status'] ?? '').toString();
                                final progress = (c['progress'] as num?)?.toDouble() ?? 0;
                                final target = (c['target'] as num?)?.toDouble() ?? 0;
                                final statusColor = _statusColor(status);
                                final statusIcon = _statusIcon(status);
                                final pct = target > 0 ? (progress / target).clamp(0.0, 1.0) : (status == 'completed' ? 1.0 : 0.0);

                                return TweenAnimationBuilder<double>(
                                  duration: Duration(milliseconds: 240 + (i * 45)),
                                  curve: Curves.easeOutCubic,
                                  tween: Tween(begin: 0, end: 1),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          _kCard,
                                          Color(0xFF101A2D),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: statusColor.withValues(alpha: 0.26)),
                                    ),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        Icon(statusIcon, size: 16, color: statusColor),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(title,
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14.5,
                                            letterSpacing: 0.15,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        )),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: statusColor.withValues(alpha: 0.38)),
                                          ),
                                          child: Text(
                                            status.isEmpty ? 'pending' : status.replaceAll('_', ' ').toUpperCase(),
                                            style: TextStyle(color: statusColor, fontSize: 9.2, fontWeight: FontWeight.w800, letterSpacing: 0.85),
                                          ),
                                        ),
                                      ]),
                                      if (desc.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          desc,
                                          style: const TextStyle(color: _kTextM, fontSize: 12.4, height: 1.3),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      if (target > 0) ...[
                                        const SizedBox(height: 10),
                                        Row(children: [
                                          Expanded(child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: LinearProgressIndicator(
                                              value: pct,
                                              minHeight: 7,
                                              backgroundColor: Colors.white12,
                                              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                                            ),
                                          )),
                                          const SizedBox(width: 10),
                                          Text('${progress.toInt()} / ${target.toInt()}',
                                            style: TextStyle(color: _kTextM, fontSize: 11.5, fontWeight: FontWeight.w800)),
                                        ]),
                                      ],
                                    ]),
                                  ),
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, 12 * (1 - value)),
                                        child: child,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4F46E5),
            Color(0xFF2979FF),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
