import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../app/scoutai_app.dart';
import '../core/network/api_client.dart';
import '../features/scouter/models/scouter_contract_draft_mapper.dart';
import '../features/scouter/models/scouter_player.dart';
import '../features/scouter/models/scouter_player_workflow.dart';
import '../features/scouter/models/scouter_player_workflow_dto.dart';
import '../features/scouter/models/scouter_player_workflow_mapper.dart';
import '../features/scouter/services/scouter_service.dart';
import '../services/api_config.dart';
import '../services/auth_storage.dart';
import '../services/jwt_utils.dart';
import '../services/pdf_download_helper.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

Future<pw.MemoryImage?> _loadScoutAiPdfLogo() async {
  try {
    final data = await rootBundle.load('assets/branding/scoutai_logo.png');
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

double _tieredAgencyCommission(double amount) {
  if (amount <= 0) return 0;
  var remaining = amount;
  var commission = 0.0;

  final firstBand = remaining <= 500000 ? remaining : 500000;
  commission += firstBand * 0.03;
  remaining -= firstBand;

  if (remaining > 0) {
    final secondBand = remaining <= 1500000 ? remaining : 1500000;
    commission += secondBand * 0.02;
    remaining -= secondBand;
  }

  if (remaining > 0) {
    commission += remaining * 0.01;
  }

  return commission;
}

class ContractWorkflowScreen extends StatefulWidget {
  const ContractWorkflowScreen({super.key});

  @override
  State<ContractWorkflowScreen> createState() => _ContractWorkflowScreenState();
}

class _ContractWorkflowScreenState extends State<ContractWorkflowScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _isScouterContext = false;

  Map<String, dynamic>? _playerWorkflow;
  Map<String, dynamic>? _playerMe;
  Uint8List? _playerSignatureBytes;
  String _playerSignatureContentType = 'image/png';
  String _playerSignatureFileName = 'player-signature.png';
  final ScouterService _scouterService = ScouterService(ApiClient());

  List<ScouterPlayer> _scouterPlayers = <ScouterPlayer>[];
  final Map<String, Uint8List?> _portraitCache = <String, Uint8List?>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _isScouterContext = args['role'] == 'scouter';
    }
    if (_loading) _load();
  }

  Future<void> _load() async {
    if (_isScouterContext) {
      await _loadScouterMode();
      return;
    }
    await _loadPlayerMode();
  }

  Future<void> _loadPlayerMode() async {
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final meRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final wfRes = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/me/player-workflow'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (meRes.statusCode >= 400) throw Exception('Failed to load profile (${meRes.statusCode})');
      if (wfRes.statusCode >= 400) throw Exception('Failed to load contract workflow (${wfRes.statusCode})');

      final me = jsonDecode(meRes.body);
      final data = jsonDecode(wfRes.body);
      final wf = (data is Map<String, dynamic> && data['workflow'] is Map)
          ? Map<String, dynamic>.from(data['workflow'] as Map)
          : null;

      if (!mounted) return;
      setState(() {
        _playerMe = me is Map<String, dynamic> ? me : null;
        _playerWorkflow = wf;
        _loading = false;
      });

      final b64 = (wf?['playerSignatureImageBase64'] ?? '').toString();
      if (b64.isNotEmpty) {
        try {
          _playerSignatureBytes = base64Decode(b64);
          _playerSignatureContentType = (wf?['playerSignatureImageContentType'] ?? 'image/png').toString();
          _playerSignatureFileName = (wf?['playerSignatureImageFileName'] ?? 'player-signature.png').toString();
        } catch (_) {
          _playerSignatureBytes = null;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadScouterMode() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _scouterService.getFavoritePlayers();

      if (!mounted) return;
      setState(() {
        _scouterPlayers = items;
        _loading = false;
      });

      for (final p in items.take(20)) {
        final id = p.id;
        if (id.isNotEmpty) {
          // Fire and forget portrait prefetch for smoother list rendering.
          // ignore: unawaited_futures
          _loadPortraitForPlayer(id);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadPortraitForPlayer(String id) async {
    if (_portraitCache.containsKey(id)) return;
    final token = await AuthStorage.loadToken();
    if (token == null) return;

    try {
      final pUri = Uri.parse('${ApiConfig.baseUrl}/players/$id/portrait?ts=${DateTime.now().millisecondsSinceEpoch}');
      final pRes = await http.get(pUri, headers: {'Authorization': 'Bearer $token'});
      final ct = (pRes.headers['content-type'] ?? '').toLowerCase();
      if (pRes.statusCode < 400 && pRes.bodyBytes.isNotEmpty && ct.startsWith('image/')) {
        _portraitCache[id] = pRes.bodyBytes;
      } else {
        _portraitCache[id] = null;
      }
      if (mounted) setState(() {});
    } catch (_) {
      _portraitCache[id] = null;
    }
  }

  Future<String> _playerSignatureQrValue() async {
    var userId = ((_playerMe?['_id'] ?? _playerMe?['id'] ?? _playerMe?['userId']) ?? '').toString().trim();
    var email = (_playerMe?['email'] ?? '').toString().trim().toLowerCase();
    var role = (_playerMe?['role'] ?? 'player').toString().trim();

    final token = await AuthStorage.loadToken();
    if (token != null) {
      final payload = decodeJwtPayload(token);
      if (userId.isEmpty) {
        userId = (payload['sub'] ?? payload['id'] ?? '').toString().trim();
      }
      if (email.isEmpty) {
        email = (payload['email'] ?? '').toString().trim().toLowerCase();
      }
      if (role.isEmpty) {
        role = (payload['role'] ?? 'player').toString().trim();
      }
    }

    final displayName = (_playerMe?['displayName'] ?? '').toString().trim();
    final fallbackName = (_playerMe?['email'] ?? 'player').toString().trim();
    final fullName = displayName.isNotEmpty ? displayName : fallbackName;
    final nameParts = fullName.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final qrPayload = <String, dynamic>{
      't': 'scoutai-signature',
      'v': 2,
      'role': role.isEmpty ? 'player' : role,
      'id': userId,
      'nom': lastName.isNotEmpty ? lastName : fullName,
      'prenom': firstName,
      'email': email,
      'picture': (_playerMe?['portraitFile'] ?? '').toString(),
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

  Future<void> _pickPlayerSignatureImage() async {
    final signatureValue = await _playerSignatureQrValue();
    final bytes = await _buildSignatureQrPng(signatureValue);
    if (bytes == null || bytes.isEmpty || !mounted) return;
    setState(() {
      _playerSignatureBytes = bytes;
      _playerSignatureContentType = 'image/png';
      _playerSignatureFileName = 'player-signature-qr-${signatureValue.hashCode.abs()}.png';
    });
  }

  Future<void> _playerWorkflowAction(String endpoint, String successMessage, {Map<String, dynamic>? payload}) async {
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/me/player-workflow/$endpoint');
      final hasPayload = payload != null && payload.isNotEmpty;
      final headers = <String, String>{'Authorization': 'Bearer $token'};
      if (hasPayload) headers['Content-Type'] = 'application/json';
      final res = await http.post(uri, headers: headers, body: hasPayload ? jsonEncode(payload) : null);
      if (!mounted) return;
      if (res.statusCode >= 400) {
        String msg = 'Action failed';
        try {
          final parsed = jsonDecode(res.body);
          if (parsed is Map && parsed['message'] is String) msg = parsed['message'].toString();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.danger));
        setState(() => _busy = false);
        return;
      }
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic> && data['workflow'] is Map) {
        setState(() {
          _playerWorkflow = Map<String, dynamic>.from(data['workflow'] as Map);
          _busy = false;
        });
      } else {
        setState(() => _busy = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage), backgroundColor: AppColors.success));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  String _numToText(dynamic value) {
    final n = (value is num) ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (n == null || n <= 0) return '';
    return n.truncateToDouble() == n ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  Future<void> _exportContractPdf({
    required Map<String, dynamic> workflow,
    required String playerName,
    String? playerGovernmentId,
  }) async {
    final draftRaw = workflow['contractDraft'];
    final draft = draftRaw is Map ? Map<String, dynamic>.from(draftRaw) : <String, dynamic>{};
    final currency = (draft['currency'] ?? 'EUR').toString();
    final fixedPrice = (workflow['fixedPrice'] as num?)?.toDouble() ?? 0;

    final doc = pw.Document();
    final scoutAiLogo = await _loadScoutAiPdfLogo();
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

    final contractRef = 'SA-${DateTime.now().year}-${playerName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase()}-${txt(playerGovernmentId).replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}';
    final playerIdLabel = txt(playerGovernmentId);
    final signaturePrimeMin = fixedPrice * 0.0075;
    final signaturePrimeMax = fixedPrice * 0.01;
    final tieredCommission = _tieredAgencyCommission(fixedPrice);

    pw.Widget sectionTitle(String title) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
    );

    final clauses = <Map<String, String>>[
      {
        'title': '1. Objet du contrat',
        'body': 'Le present contrat fixe les conditions professionnelles liant le Club, le Joueur, l Intermediaire et l Agence pour la saison contractuelle, y compris les obligations sportives, financieres et administratives.'
      },
      {
        'title': '2. Duree et execution',
        'body': 'Le contrat prend effet a la date de debut indiquee et se termine a la date de fin prevue. Tout renouvellement doit faire l objet d un accord ecrit signe par les Parties avant echeance.'
      },
      {
        'title': '3. Obligations du Joueur',
        'body': 'Le Joueur s engage a participer aux entrainements, competitions et obligations disciplinaires du Club, a maintenir sa condition physique et a respecter les reglements sportifs applicables.'
      },
      {
        'title': '4. Obligations du Club',
        'body': 'Le Club garantit l encadrement technique et medical necessaire, le paiement des remunerations dues et des conditions de travail conformes aux exigences du football professionnel.'
      },
      {
        'title': '5. Remuneration',
        'body': 'La remuneration comprend une base fixe et des composantes variables liees aux performances individuelles et collectives. Les modalites de calcul et d exigibilite figurent dans les termes financiers ci-dessus.'
      },
      {
        'title': '6. Confidentialite et donnees',
        'body': 'Les Parties s obligent a la confidentialite sur les informations contractuelles, medicales et strategiques. Les donnees personnelles sont traitees uniquement pour l execution du contrat et la conformite legale.'
      },
      {
        'title': '7. Ethique et integrite',
        'body': 'Le Joueur et le Club respectent les obligations anti dopage, anti corruption et d integrite sportive. Toute violation grave peut constituer un motif de rupture anticipee pour faute grave.'
      },
      {
        'title': '8. Blessure et indisponibilite',
        'body': 'En cas de blessure, un protocole medical de suivi est applique. Les obligations financieres sont traitees selon la reglementation locale, la convention du Club et les clauses complementaires convenues.'
      },
      {
        'title': '9. Resiliation anticipee',
        'body': 'Toute resiliation anticipee requiert un fondement contractuel ou legal, une notification ecrite et, sauf urgence, une tentative de regularisation dans un delai raisonnable.'
      },
      {
        'title': '10. Droit applicable et litiges',
        'body': 'Le present contrat est soumis au droit applicable du territoire convenu entre les Parties. Les litiges sont traites prioritairement a l amiable, puis devant la juridiction competente.'
      },
    ];

    final agencyInfo = <String>[
      'Agency legal name: ScoutAI Agency',
      'Agency contact: legal@scoutai.pro',
      'Agency role: digital governance, contract traceability, and compliance oversight.',
      'Signature pre-contract No refund [Prix variable] : prime de signature 0,75 - 1% ($currency ${signaturePrimeMin.toStringAsFixed(2)} to $currency ${signaturePrimeMax.toStringAsFixed(2)}).',
      'Agency commission (tiered): $currency ${tieredCommission.toStringAsFixed(2)}.',
      '3% on the portion up to EUR 500,000.',
      '2% on the portion between EUR 500,001 and EUR 2,000,000.',
      '1% on any portion exceeding EUR 2,000,000.',
      'Agency evidence model: digital signature metadata and QR-backed audit trail.',
    ];

    final agencyClauses = <Map<String, String>>[
      {
        'title': 'A1. Agency Mandate',
        'body': 'ScoutAI Agency is mandated to administer digital compliance controls, preserve documentary traceability, and support lawful execution of this contract lifecycle.',
      },
      {
        'title': 'A2. Commission Trigger',
        'body': 'The agency commission is tiered by tranche: 3% up to EUR 500,000, 2% from EUR 500,001 to EUR 2,000,000, and 1% above EUR 2,000,000. The pre-contract signature prime is variable at 0,75% to 1% and is non-refundable.',
      },
      {
        'title': 'A3. Audit and Integrity',
        'body': 'Parties acknowledge that signature timestamps, identity metadata, and platform logs may be used as evidentiary records for compliance review and dispute resolution.',
      },
    ];

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
      'Article 15 : Signature pre-contract No refund [Prix variable] : prime de signature 0,75 - 1%.',
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
      'Player legal side: sporting services, discipline, confidentiality, and medical compliance obligations are binding and enforceable.',
      'Scouter legal side: lawful intermediation, transparent negotiation conduct, and documented communication chain are mandatory.',
      'ScoutAI Agency legal side: governance oversight, auditable controls, and tiered commission entitlement (3%/2%/1%) are expressly recognized.',
      'Common legal side: parties accept digital signature records, verified identity metadata, and legal dispute process under governing jurisdiction.',
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
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 24),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Contract Ref: $contractRef  |  Page ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF22384A),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 86,
                  padding: const pw.EdgeInsets.only(right: 6),
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Container(
                        width: 56,
                        height: 56,
                        decoration: pw.BoxDecoration(
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
                          gradient: const pw.LinearGradient(
                            begin: pw.Alignment.topLeft,
                            end: pw.Alignment.bottomRight,
                            colors: [
                              PdfColor.fromInt(0xFF38BDF8),
                              PdfColor.fromInt(0xFF2563EB),
                              PdfColor.fromInt(0xFFA3E635),
                            ],
                          ),
                        ),
                        child: scoutAiLogo != null
                          ? pw.Image(scoutAiLogo, fit: pw.BoxFit.contain)
                            : pw.Stack(
                                children: [
                                  pw.Positioned(
                                    left: 23.6,
                                    top: 14.0,
                                    child: pw.Transform.rotate(
                                      angle: 0.46,
                                      child: pw.Container(
                                        width: 9.2,
                                        height: 3.8,
                                        decoration: const pw.BoxDecoration(
                                          color: PdfColor.fromInt(0xFFFF5A3D),
                                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(1.9)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  pw.Positioned(
                                    left: 28.2,
                                    top: 19.3,
                                    child: pw.Transform.rotate(
                                      angle: -0.18,
                                      child: pw.Container(
                                        width: 8.6,
                                        height: 4.0,
                                        decoration: const pw.BoxDecoration(
                                          color: PdfColor.fromInt(0xFFFFD33A),
                                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(2.0)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  pw.Positioned(
                                    left: 24.9,
                                    top: 25.4,
                                    child: pw.Transform.rotate(
                                      angle: 0.50,
                                      child: pw.Container(
                                        width: 10.0,
                                        height: 3.8,
                                        decoration: const pw.BoxDecoration(
                                          color: PdfColor.fromInt(0xFF2D67FF),
                                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(1.9)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('ScoutAI', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        'SCOUTAI',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.5,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('ScoutAI Football', style: const pw.TextStyle(fontSize: 11.8, color: PdfColors.white)),
                    ],
                  ),
                ),
                pw.Container(
                  width: 132,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColors.blueGrey200),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('CONTRACT REF', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                      pw.Text(contractRef, style: const pw.TextStyle(fontSize: 6.5)),
                      pw.SizedBox(height: 3),
                      pw.Text('EFFECTIVE DATE', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                      pw.Text('${txt(draft['startDate'])} to ${txt(draft['endDate'])}', style: const pw.TextStyle(fontSize: 6.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'OFFICIAL EMPLOYMENT AGREEMENT',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFD6C28F)),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('BETWEEN:', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('1. THE CLUB: ${txt(draft['clubName'])}, a professional football club under applicable federation regulations.', style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.2)),
          pw.Text('2. THE PLAYER: ${txt(playerName)} (ID: $playerIdLabel), registered for professional participation and contractual obligations.', style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.2)),
          pw.Text('3. THE AGENCY: ScoutAI Agency (legal@scoutai.pro), compliance and digital governance representative.', style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.2)),
          pw.Text('4. THE SCOUTER: ID ${txt(draft['scouterIntermediaryId'])}, acting as authorized intermediary.', style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.2)),
          pw.SizedBox(height: 10),
          pw.Text('ARTICLE 1: TERM OF ENGAGEMENT', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            '1.1 The term of this contract begins on ${txt(draft['startDate'])} and expires on ${txt(draft['endDate'])}. The player shall remain available for official sporting duties throughout the term under club and federation rules.',
            style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.22),
          ),
          pw.SizedBox(height: 8),
          pw.Text('ARTICLE 3: COMPENSATION AND REMUNERATION', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('3.1 Fixed annual remuneration (base): $currency ${_numToText(draft['fixedBaseSalary'])}', style: const pw.TextStyle(fontSize: 9.1)),
          pw.Text('3.2 Signature pre-contract No refund [Prix variable] : prime de signature 0,75 - 1% ($currency ${signaturePrimeMin.toStringAsFixed(2)} to $currency ${signaturePrimeMax.toStringAsFixed(2)})', style: const pw.TextStyle(fontSize: 9.1)),
          pw.Text('3.3 Performance-related bonuses:', style: const pw.TextStyle(fontSize: 9.1)),
          pw.Bullet(text: 'Appearance bonus: $currency ${_numToText(draft['bonusPerAppearance'])}'),
          pw.Bullet(text: 'Goal/Clean sheet bonus: $currency ${_numToText(draft['bonusGoalOrCleanSheet'])}'),
          pw.Bullet(text: 'Team trophy bonus: $currency ${_numToText(draft['bonusTeamTrophy'])}'),
          pw.Text('3.4 Transfer provisions and release clause: $currency ${_numToText(draft['releaseClauseAmount'])}', style: const pw.TextStyle(fontSize: 9.1)),
          pw.Text('3.5 Fees and commissions:', style: const pw.TextStyle(fontSize: 9.1)),
          pw.Bullet(text: 'Fixed contract amount: $currency ${fixedPrice.toStringAsFixed(2)}'),
          pw.Bullet(text: 'Agency commission (tiered estimate): $currency ${tieredCommission.toStringAsFixed(2)}'),
          pw.Bullet(text: '3% on the portion up to EUR 500,000'),
          pw.Bullet(text: '2% on the portion between EUR 500,001 and EUR 2,000,000'),
          pw.Bullet(text: '1% on any portion exceeding EUR 2,000,000'),
          pw.Bullet(text: 'Verification fee: USD 30 (paid by platform)'),
          pw.SizedBox(height: 10),
          sectionTitle('Agency Information'),
          ...agencyInfo.map((line) => pw.Bullet(text: line)),
          pw.SizedBox(height: 8),
          sectionTitle('Agency Clauses'),
          ...agencyClauses.map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(9),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(c['title']!, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    pw.Text(c['body']!, style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.2)),
                  ],
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          sectionTitle('Termination Clause'),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey200)),
            child: pw.Text(txt(draft['terminationForCauseText'])),
          ),
          pw.SizedBox(height: 12),
          sectionTitle('Professional Clauses'),
          ...clauses.map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(9),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(c['title']!, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    pw.Text(c['body']!, style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.2)),
                  ],
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          sectionTitle('Cadre Juridique Du Contrat Professionnel'),
          ...legalArticles.map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(c, style: const pw.TextStyle(fontSize: 9.4, lineSpacing: 1.25)),
            ),
          ),
          pw.SizedBox(height: 8),
          sectionTitle('Juridical Responsibilities By Party'),
          ...partyLegalNotes.map(
            (c) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(c, style: const pw.TextStyle(fontSize: 9.4, lineSpacing: 1.25)),
            ),
          ),
          pw.SizedBox(height: 10),
          sectionTitle('Annexes Contractuelles Detaillees'),
          pw.Text('Annex A - Barreme financier: grille complete des primes de presence, victoire, objectifs et performances collectives.', style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.2)),
          pw.Text('Annex B - Commission ScoutAI par tranches (3%/2%/1%): base de calcul, echeancier de facturation, conditions de preuve de paiement.', style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.2)),
          pw.Text('Annex C - Protocole medical: examens, suivi blessure, reprise sportive, avis medecin et responsabilites des parties.', style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.2)),
          pw.Text('Annex D - Clause de rupture anticipee: faute grave, procedure contradictoire, indemnite compensatoire et voies de recours.', style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.2)),
          pw.Text('Annex E - Droits a l image: usages collectifs/individuels, repartition des revenus, obligations media et sponsors.', style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.2)),
          pw.Text('Annex F - Conformite et ethique: anti dopage, anti corruption, paris sportifs, confidentialite et sanctions.', style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.2)),
          pw.Text('Annex G - Calendrier administratif: homologation ligue, visa sportif, enregistrement federation, delais de retour selection.', style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.2)),
          pw.Text('Annex H - Grille disciplinaire: manquements, amendes, suspension des primes, procedure contradictoire et recours interne.', style: const pw.TextStyle(fontSize: 9.2, lineSpacing: 1.2)),
          pw.SizedBox(height: 5),
          pw.Bullet(text: 'Detail A-H.1: chaque annexe indique autorite competente, delai de traitement, pieces justificatives et signatures requises.'),
          pw.Bullet(text: 'Detail A-H.2: tout paiement, sanction ou exception doit etre trace avec reference de dossier et horodatage contractuel.'),
          pw.Bullet(text: 'Detail A-H.3: en cas de conflit entre annexes, la clause de priorite juridique est appliquee avec notification ecrite aux parties.'),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Text(
              'Annexes effect: each annex forms an integral and binding part of this contract. In case of inconsistency, the main body prevails unless the annex expressly states mandatory override for regulatory compliance.',
              style: const pw.TextStyle(fontSize: 8.8, lineSpacing: 1.2, color: PdfColors.blueGrey800),
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
                      pw.Text('Player', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
                      pw.Text('Scouter', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Text(
              'By signing this agreement, each Party confirms legal capacity, understanding of contractual obligations, and acceptance of digital records and QR-based signature evidence as part of the contractual audit trail.',
              style: const pw.TextStyle(fontSize: 9.5),
            ),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final safe = playerName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final fileName = 'ScoutAI_Contract_$safe.pdf';
    final didWebDownload = await triggerPdfDownload(bytes, fileName);
    if (didWebDownload) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contract PDF downloaded: $fileName'), backgroundColor: AppColors.success),
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
      SnackBar(content: Text('Contract PDF downloaded: $fileName'), backgroundColor: AppColors.success),
    );
  }

  Widget _statusPill(String label, String value) {
    final raw = value.toLowerCase();
    final good = raw == 'approved' || raw == 'verified' || raw == 'yes' || raw == 'completed';
    final bad = raw == 'cancelled' || raw == 'rejected';
    final bg = good
        ? AppColors.success.withValues(alpha: 0.2)
        : bad
            ? AppColors.danger.withValues(alpha: 0.2)
            : AppColors.surface.withValues(alpha: 0.6);
    final fg = good ? AppColors.success : (bad ? AppColors.danger : Colors.white70);
    final icon = good
        ? Icons.check_circle_rounded
        : bad
            ? Icons.cancel_rounded
            : Icons.timelapse_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Text('$label: $value', style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildPlayerPanel() {
    final workflow = _playerWorkflow;
    final fixed = (workflow?['fixedPrice'] as num?)?.toDouble() ?? 0;
    final playerIdNum = (_playerMe?['playerIdNumber'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surf(context).withValues(alpha: 0.88),
            AppColors.surf2(context).withValues(alpha: 0.74),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PLAYER CONTRACT WORKFLOW', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.7)),
          const SizedBox(height: 6),
          const Text('Review status, sign, and export the final agreement.', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusPill('Verification', (workflow?['verificationStatus'] ?? 'not_requested').toString()),
              _statusPill('Pre-contract', (workflow?['preContractStatus'] ?? 'none').toString()),
              _statusPill('Platform Fee', workflow?['scouterPlatformFeePaid'] == true ? 'paid (optional)' : 'optional'),
              _statusPill('Scouter Signed', workflow?['scouterSignedContract'] == true ? 'yes' : 'pending'),
              _statusPill('Player Signed', workflow?['contractSignedByPlayer'] == true ? 'yes' : 'pending'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surf2(context).withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Player ID Number: ${playerIdNum.isEmpty ? '-' : playerIdNum}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                const SizedBox(height: 7),
                Text('Fixed contract price: EUR ${fixed.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Text('Agency commission (tiered est.): EUR ${_tieredAgencyCommission(fixed).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                const Text('Expert verification fee: USD 30 (paid by platform).', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickPlayerSignatureImage,
                icon: const Icon(Icons.qr_code_2),
                label: Text(_playerSignatureBytes == null ? 'Generate My Unique QR Signature' : 'Regenerate My QR Signature'),
              ),
              if (_playerSignatureBytes != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _playerSignatureFileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
          if (_playerSignatureBytes != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              padding: const EdgeInsets.all(8),
              child: Image.memory(_playerSignatureBytes!, fit: BoxFit.contain),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy || (workflow?['preContractStatus'] != 'approved')
                    ? null
                    : () {
                        if (_playerSignatureBytes == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generate your unique QR signature first')));
                          return;
                        }
                        _playerWorkflowAction(
                          'sign-pre-contract',
                          'Contract signed successfully',
                          payload: {
                            'signatureImageBase64': base64Encode(_playerSignatureBytes!),
                            'signatureImageContentType': _playerSignatureContentType,
                            'signatureImageFileName': _playerSignatureFileName,
                          },
                        );
                      },
                icon: _busy
                    ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.edit_note_rounded),
                label: const Text('Sign Contract Online'),
              ),
              OutlinedButton(
                onPressed: _busy || (workflow?['contractSignedByPlayer'] != true)
                    ? null
                    : () => _playerWorkflowAction('complete-online-session', 'Online session marked as completed'),
                child: const Text('Complete Online Session'),
              ),
              OutlinedButton.icon(
                onPressed: workflow?['preContractStatus'] == 'approved'
                    ? () => _exportContractPdf(
                          workflow: workflow!,
                          playerName: (_playerMe?['displayName'] ?? _playerMe?['email'] ?? 'Player').toString(),
                          playerGovernmentId: playerIdNum,
                        )
                    : null,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export Contract PDF'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScouterPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surf(context).withValues(alpha: 0.88),
            AppColors.surf2(context).withValues(alpha: 0.74),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SCOUTER CONTRACT WORKFLOW', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          const Text('Open a player to draft and sign a complete pre-contract.', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          if (_scouterPlayers.isEmpty)
            const Text('No followed players found.', style: TextStyle(color: Colors.white70))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _scouterPlayers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = _scouterPlayers[i];
                final id = p.id;
                final portrait = _portraitCache[id];
                final name = p.displayName;
                final pid = p.playerIdNumber;
                return InkWell(
                  onTap: () async {
                    await _loadPortraitForPlayer(id);
                    if (!mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ScouterContractEditorScreen(
                          player: p,
                          portraitBytes: _portraitCache[id],
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      color: AppColors.surf2(context).withValues(alpha: 0.45),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white10,
                          backgroundImage: portrait != null ? MemoryImage(portrait) : null,
                          child: portrait == null ? const Icon(Icons.person, color: Colors.white70) : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                              Text('Player ID: ${pid.isEmpty ? '-' : pid}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white70),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const GradientScaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return GradientScaffold(
        appBar: AppBar(
          title: const Text('Contract Workflow'),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).pushNamed(AppRoutes.notifications),
              icon: const Icon(Icons.notifications_outlined),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Contract Workflow'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.notifications),
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _isScouterContext ? _buildScouterPanel() : _buildPlayerPanel(),
        ],
      ),
    );
  }
}

class ScouterContractEditorScreen extends StatefulWidget {
  const ScouterContractEditorScreen({
    super.key,
    required this.player,
    this.portraitBytes,
  });

  final ScouterPlayer player;
  final Uint8List? portraitBytes;

  @override
  State<ScouterContractEditorScreen> createState() => _ScouterContractEditorScreenState();
}

class _ScouterContractEditorScreenState extends State<ScouterContractEditorScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _busy = false;
  String? _error;

  ScouterPlayerWorkflow? _workflow;
  final ScouterService _scouterService = ScouterService(ApiClient());

  final _fixedPriceCtrl = TextEditingController();
  final _clubNameCtrl = TextEditingController();
  final _clubOfficialNameCtrl = TextEditingController();
  final _startDateCtrl = TextEditingController();
  final _endDateCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'EUR');
  final _fixedBaseSalaryCtrl = TextEditingController();
  final _signingFeeCtrl = TextEditingController();
  final _marketValueCtrl = TextEditingController();
  final _bonusAppearanceCtrl = TextEditingController();
  final _bonusGoalCtrl = TextEditingController();
  final _bonusTrophyCtrl = TextEditingController();
  final _releaseClauseCtrl = TextEditingController();
  final _terminationCtrl = TextEditingController();
  final _intermediaryCtrl = TextEditingController();
  String _salaryPeriod = 'monthly';

  Uint8List? _scouterSignatureBytes;
  String _scouterSignatureContentType = 'image/png';
  String _scouterSignatureFileName = 'scouter-signature.png';
  late final AnimationController _introController;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fixedPriceCtrl.addListener(_onFormChanged);
    _currencyCtrl.addListener(_onFormChanged);
    _startDateCtrl.addListener(_onFormChanged);
    _endDateCtrl.addListener(_onFormChanged);
    _clubNameCtrl.addListener(_onFormChanged);
    _load();
  }

  @override
  void dispose() {
    _introController.dispose();
    _fixedPriceCtrl.removeListener(_onFormChanged);
    _currencyCtrl.removeListener(_onFormChanged);
    _startDateCtrl.removeListener(_onFormChanged);
    _endDateCtrl.removeListener(_onFormChanged);
    _clubNameCtrl.removeListener(_onFormChanged);
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

  String get _playerId => widget.player.id;

  void _onFormChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _isoDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _setTodayAsStart() {
    _startDateCtrl.text = _isoDate(DateTime.now());
  }

  void _setEndInYears(int years) {
    final from = DateTime.tryParse(_startDateCtrl.text.trim()) ?? DateTime.now();
    _endDateCtrl.text = _isoDate(DateTime(from.year + years, from.month, from.day));
  }

  Future<void> _pickDate(TextEditingController ctrl, {required String title}) async {
    final initial = DateTime.tryParse(ctrl.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      helpText: title,
    );
    if (picked == null || !mounted) return;
    setState(() {
      ctrl.text = _isoDate(picked);
    });
  }

  List<double> _amountPresetsFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('fixed price') || l.contains('market value') || l.contains('release clause')) {
      return const [10000, 25000, 50000, 100000, 250000, 500000];
    }
    if (l.contains('bonus')) {
      return const [500, 1000, 2000, 5000, 10000, 20000];
    }
    return const [1000, 2500, 5000, 10000, 25000, 50000];
  }

  String _amountText(double amount) {
    if (amount.truncateToDouble() == amount) return amount.toStringAsFixed(0);
    return amount.toStringAsFixed(2);
  }

  String _currencySymbol() {
    final c = _currencyCtrl.text.trim().toUpperCase();
    switch (c) {
      case 'USD':
        return r'$';
      case 'GBP':
        return '£';
      case 'AED':
        return 'AED';
      case 'KWD':
      case 'JOD':
      case 'IQD':
      case 'DZD':
      case 'TND':
      case 'LYD':
      case 'DINAR':
        return 'D';
      case 'EUR':
      default:
        return c.isEmpty ? '€' : c;
    }
  }

  Future<void> _pickCurrencyQuick() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final options = const <Map<String, String>>[
          {'code': 'EUR', 'name': 'Euro'},
          {'code': 'USD', 'name': 'US Dollar'},
          {'code': 'GBP', 'name': 'British Pound'},
          {'code': 'AED', 'name': 'UAE Dirham'},
          {'code': 'DZD', 'name': 'Algerian Dinar'},
          {'code': 'IQD', 'name': 'Iraqi Dinar'},
          {'code': 'JOD', 'name': 'Jordanian Dinar'},
          {'code': 'KWD', 'name': 'Kuwaiti Dinar'},
        ];
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
            itemBuilder: (_, i) {
              final item = options[i];
              return ListTile(
                title: Text(item['code']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: Text(item['name']!, style: const TextStyle(color: Colors.white70)),
                onTap: () => Navigator.of(ctx).pop(item['code']),
              );
            },
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() => _currencyCtrl.text = selected.toUpperCase());
  }

  Future<void> _pickAmount(TextEditingController ctrl, String label) async {
    final presets = _amountPresetsFor(label);
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.surf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select $label', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Tap to select quickly or type manually in the field.', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets
                    .map(
                      (amount) => ActionChip(
                        label: Text(
                          '${_currencySymbol()} ${_amountText(amount)}',
                        ),
                        onPressed: () => Navigator.of(ctx).pop(amount),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() {
      ctrl.text = _amountText(selected);
    });
  }

  Widget _animatedIn({
    required int index,
    required Widget child,
  }) {
    final begin = (index * 0.08).clamp(0.0, 0.85);
    final end = (begin + 0.2).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _introController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (_, c) {
        final t = anim.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: c,
          ),
        );
      },
    );
  }

  String _numToText(dynamic value) {
    final n = (value is num) ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (n == null || n <= 0) return '';
    return n.truncateToDouble() == n ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  double _parseMoney(String raw) => double.tryParse(raw.trim()) ?? 0;

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

  ScouterPlayerWorkflow? _asWorkflow(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return ScouterPlayerWorkflowMapper.toEntity(ScouterPlayerWorkflowDto.fromJson(raw));
    }
    if (raw is Map) {
      return ScouterPlayerWorkflowMapper.toEntity(
        ScouterPlayerWorkflowDto.fromJson(Map<String, dynamic>.from(raw)),
      );
    }
    return null;
  }

  void _hydrateFromWorkflow(ScouterPlayerWorkflow wf) {
    final draft = wf.contractDraft;
    final fp = wf.fixedPrice;

    _fixedPriceCtrl.text = fp <= 0 ? '' : fp.toStringAsFixed(fp.truncateToDouble() == fp ? 0 : 2);
    _clubNameCtrl.text = draft.clubName;
    _clubOfficialNameCtrl.text = draft.clubOfficialName;
    _startDateCtrl.text = draft.startDate;
    _endDateCtrl.text = draft.endDate;
    _currencyCtrl.text = draft.currency;
    _salaryPeriod = draft.salaryPeriod == 'weekly' ? 'weekly' : 'monthly';
    _fixedBaseSalaryCtrl.text = _numToText(draft.fixedBaseSalary);
    _signingFeeCtrl.text = _numToText(draft.signingOnFee);
    _marketValueCtrl.text = _numToText(draft.marketValue);
    _bonusAppearanceCtrl.text = _numToText(draft.bonusPerAppearance);
    _bonusGoalCtrl.text = _numToText(draft.bonusGoalOrCleanSheet);
    _bonusTrophyCtrl.text = _numToText(draft.bonusTeamTrophy);
    _releaseClauseCtrl.text = _numToText(draft.releaseClauseAmount);
    _terminationCtrl.text = draft.terminationForCauseText;
    _intermediaryCtrl.text = draft.scouterIntermediaryId;

    final sigB64 = wf.scouterSignatureImageBase64;
    if (sigB64.isNotEmpty) {
      try {
        _scouterSignatureBytes = base64Decode(sigB64);
        _scouterSignatureContentType = wf.scouterSignatureImageContentType.isEmpty
            ? 'image/png'
            : wf.scouterSignatureImageContentType;
        _scouterSignatureFileName = wf.scouterSignatureImageFileName.isEmpty
            ? 'scouter-signature.png'
            : wf.scouterSignatureImageFileName;
      } catch (_) {
        _scouterSignatureBytes = null;
      }
    }
  }

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

    final qrPayload = <String, dynamic>{
      't': 'scoutai-signature',
      'v': 2,
      'role': role,
      'id': userId,
      'nom': lastName.isNotEmpty ? lastName : fallbackName,
      'prenom': firstName,
      'email': email,
      'picture': 'portrait-loaded',
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

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final workflow = await _scouterService.getScouterPlayerWorkflow(_playerId);
      final typedWorkflow = workflow ?? const ScouterPlayerWorkflow.empty();

      if (!mounted) return;
      setState(() {
        _workflow = typedWorkflow;
        _loading = false;
      });
      _hydrateFromWorkflow(typedWorkflow);
      _introController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _pickScouterSignatureImage() async {
    final signatureValue = await _scouterSignatureQrValue();
    final bytes = await _buildSignatureQrPng(signatureValue);
    if (bytes == null || bytes.isEmpty || !mounted) return;
    setState(() {
      _scouterSignatureBytes = bytes;
      _scouterSignatureContentType = 'image/png';
      _scouterSignatureFileName = 'scouter-signature-qr-${signatureValue.hashCode.abs()}.png';
    });
  }

  Future<void> _updateScouterDecision(String decision) async {
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/admin/players/$_playerId/scouter-decision');
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
        setState(() => _busy = false);
        return;
      }
      final data = jsonDecode(res.body);
      final wf = data is Map<String, dynamic> ? _asWorkflow(data['workflow']) : null;
      if (wf != null) {
        setState(() {
          _workflow = wf;
          _busy = false;
        });
        _hydrateFromWorkflow(wf);
      } else {
        setState(() => _busy = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _updatePreContract({required String status}) async {
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;
    if (_intermediaryCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Scouter ID')),
      );
      return;
    }
    if (status == 'approved' && _scouterSignatureBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate your unique QR signature before approval')),
      );
      return;
    }
    final fixedPrice = double.tryParse(_fixedPriceCtrl.text.trim()) ?? 0;

    setState(() => _busy = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/admin/players/$_playerId/pre-contract');
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
          'clubOfficialName': _clubNameCtrl.text.trim(),
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
        setState(() => _busy = false);
        return;
      }
      final data = jsonDecode(res.body);
      final wf = data is Map<String, dynamic> ? _asWorkflow(data['workflow']) : null;
      if (wf != null) {
        final draft = wf.contractDraft;
        setState(() {
          _workflow = wf;
          _intermediaryCtrl.text = draft.scouterIntermediaryId;
          _busy = false;
        });
        _hydrateFromWorkflow(wf);
      } else {
        setState(() => _busy = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _startNewTestContract() async {
    final token = await AuthStorage.loadToken();
    if (token == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/admin/players/$_playerId/pre-contract');
      final res = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'status': 'draft',
          'scouterSignNow': false,
          'scouterSignatureImageBase64': '',
          'scouterSignatureImageContentType': '',
          'scouterSignatureImageFileName': '',
        }),
      );

      if (!mounted) return;
      if (res.statusCode >= 400) {
        final msg = _extractApiMessage(res.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.isEmpty ? 'Could not start new test contract' : msg)),
        );
        setState(() => _busy = false);
        return;
      }

      final data = jsonDecode(res.body);
      final wf = data is Map<String, dynamic> ? _asWorkflow(data['workflow']) : null;
      if (wf != null) {
        setState(() {
          _workflow = wf;
          _scouterSignatureBytes = null;
          _scouterSignatureContentType = 'image/png';
          _scouterSignatureFileName = 'scouter-signature.png';
          _busy = false;
        });
        _hydrateFromWorkflow(wf);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New test contract started. You can sign and pay again.')),
        );
      } else {
        setState(() => _busy = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Widget _statusPill(String label, String value) {
    final raw = value.toLowerCase();
    final good = raw == 'approved' || raw == 'verified' || raw == 'yes' || raw == 'completed';
    final bad = raw == 'cancelled' || raw == 'rejected';
    final bg = good
        ? AppColors.success.withValues(alpha: 0.2)
        : bad
            ? AppColors.danger.withValues(alpha: 0.2)
            : AppColors.surface.withValues(alpha: 0.6);
    final fg = good ? AppColors.success : (bad ? AppColors.danger : Colors.white70);
    final icon = good
        ? Icons.check_circle_rounded
        : bad
            ? Icons.cancel_rounded
            : Icons.timelapse_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    String? prefix,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    const radius = 14.0;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: AppColors.surf2(context).withValues(alpha: 0.62),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      prefixStyle: const TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w700),
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 14),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surf(context).withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _moneyField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _fieldDecoration(
        label: label,
        prefix: '${_currencySymbol()} ',
        suffixIcon: IconButton(
          tooltip: 'Select amount',
          onPressed: _busy ? null : () => _pickAmount(ctrl, label),
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
        ),
      ),
    );
  }

  Future<void> _exportContractPdf() async {
    final workflow = _workflow;
    if (workflow == null) return;
    final draft = ScouterContractDraftMapper.toDto(workflow.contractDraft).toJson();
    final currency = (draft['currency'] ?? 'EUR').toString();
    final fixedPrice = workflow.fixedPrice;

    final doc = pw.Document();
    final scoutAiLogo = await _loadScoutAiPdfLogo();
    pw.MemoryImage? scouterSig;
    pw.MemoryImage? playerSig;
    pw.MemoryImage? agencySig;
    try {
      final b64 = workflow.scouterSignatureImageBase64;
      if (b64.isNotEmpty) scouterSig = pw.MemoryImage(base64Decode(b64));
    } catch (_) {}
    try {
      final b64 = workflow.playerSignatureImageBase64;
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

    final playerName = widget.player.displayName;
    final playerIdNum = widget.player.playerIdNumber.isEmpty ? '-' : widget.player.playerIdNumber;

    final signedByPlayer = workflow.contractSignedByPlayer;
    final signedByScouter = workflow.scouterSignedContract;
    final agencySigBox = agencySig == null
      ? pw.Text('Auto-applied QR', style: const pw.TextStyle(fontSize: 9))
      : pw.Image(agencySig, height: 52, fit: pw.BoxFit.contain);

    String txt(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? '-' : s;
    }

    final clubName = txt(draft['clubName']);
    final scouterId = txt((draft['scouterIntermediaryId'] ?? _intermediaryCtrl.text.trim()));
    final contractRef = 'SA-${DateTime.now().year}-${playerName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase()}-${playerIdNum.replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}';
    final playerIdLabel = playerIdNum;
    final signaturePrimeMin = fixedPrice * 0.0075;
    final signaturePrimeMax = fixedPrice * 0.01;
    final tieredCommission = _tieredAgencyCommission(fixedPrice);

    final clauses = <Map<String, String>>[
      {
        'title': '1. Purpose and legal scope',
        'body': 'This contract governs the professional football relationship among the Club, Player, Intermediary and ScoutAI Agency, including sporting obligations, compensation framework and compliance controls.'
      },
      {
        'title': '2. Duration and renewal',
        'body': 'The agreement is valid for the term indicated in this document. Any extension, amendment or renewal requires prior written consent and signature by all required parties.'
      },
      {
        'title': '3. Sporting commitments',
        'body': 'The Player commits to training, official matches, disciplinary standards, physical conditioning and competition rules. The Club commits to provide professional sporting and medical support.'
      },
      {
        'title': '4. Compensation and bonuses',
        'body': 'Compensation includes fixed salary and variable incentives linked to measurable performance and collective outcomes. Payment cycles and amount references are defined in the financial terms section.'
      },
      {
        'title': '5. Confidentiality and data protection',
        'body': 'All parties maintain confidentiality for contractual, financial and medical information. Personal data processing is limited to contract performance, compliance and auditable administration.'
      },
      {
        'title': '6. Termination and dispute handling',
        'body': 'Early termination must follow lawful grounds and written procedure. Parties shall attempt amicable settlement first, then competent jurisdiction under applicable law if required.'
      },
    ];

    final agencyInfo = <String>[
      'Agency legal name: ScoutAI Agency',
      'Agency contact: legal@scoutai.pro',
      'Agency role: digital governance, contract traceability, and compliance oversight.',
      'Signature pre-contract No refund [Prix variable] : prime de signature 0,75 - 1% ($currency ${signaturePrimeMin.toStringAsFixed(2)} to $currency ${signaturePrimeMax.toStringAsFixed(2)}).',
      'Agency commission (tiered): $currency ${tieredCommission.toStringAsFixed(2)}.',
      '3% on the portion up to EUR 500,000.',
      '2% on the portion between EUR 500,001 and EUR 2,000,000.',
      '1% on any portion exceeding EUR 2,000,000.',
      'Agency evidence model: digital signature metadata and QR-backed audit trail.',
    ];

    final agencyClauses = <Map<String, String>>[
      {
        'title': 'A1. Agency Mandate',
        'body': 'ScoutAI Agency administers digital compliance controls, preserves traceability records, and supports lawful execution monitoring for all parties.',
      },
      {
        'title': 'A2. Commission Trigger',
        'body': 'The agency commission is tiered by tranche: 3% up to EUR 500,000, 2% from EUR 500,001 to EUR 2,000,000, and 1% above EUR 2,000,000. The pre-contract signature prime is variable at 0,75% to 1% and is non-refundable.',
      },
      {
        'title': 'A3. Audit and Integrity',
        'body': 'Signature timestamps, identity metadata, and platform logs are recognized as admissible records for compliance checks and dispute handling.',
      },
    ];

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
      'Article 15 : Signature pre-contract No refund [Prix variable] : prime de signature 0,75 - 1%.',
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
      'Player legal side: contractual sporting obligations, discipline, confidentiality, and regulated medical compliance.',
      'Scouter legal side: lawful intermediary role, transparency of negotiation acts, and evidentiary recordkeeping.',
      'ScoutAI Agency legal side: enforceable tiered commission (3%/2%/1%), compliance governance, and legal audit trail management.',
      'Common legal side: all parties acknowledge digital signature legitimacy and jurisdictional dispute pathway.',
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Contract Ref: $contractRef  |  Page ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF22384A),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 86,
                    padding: const pw.EdgeInsets.only(right: 6),
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Container(
                          width: 56,
                          height: 56,
                          decoration: pw.BoxDecoration(
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
                            gradient: const pw.LinearGradient(
                              begin: pw.Alignment.topLeft,
                              end: pw.Alignment.bottomRight,
                              colors: [
                                PdfColor.fromInt(0xFF38BDF8),
                                PdfColor.fromInt(0xFF2563EB),
                                PdfColor.fromInt(0xFFA3E635),
                              ],
                            ),
                          ),
                          child: scoutAiLogo != null
                              ? pw.Image(scoutAiLogo, fit: pw.BoxFit.contain)
                              : pw.Stack(
                                  children: [
                                    pw.Positioned(
                                      left: 23.6,
                                      top: 14.0,
                                      child: pw.Transform.rotate(
                                        angle: 0.46,
                                        child: pw.Container(
                                          width: 9.2,
                                          height: 3.8,
                                          decoration: const pw.BoxDecoration(
                                            color: PdfColor.fromInt(0xFFFF5A3D),
                                            borderRadius: pw.BorderRadius.all(pw.Radius.circular(1.9)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    pw.Positioned(
                                      left: 28.2,
                                      top: 19.3,
                                      child: pw.Transform.rotate(
                                        angle: -0.18,
                                        child: pw.Container(
                                          width: 8.6,
                                          height: 4.0,
                                          decoration: const pw.BoxDecoration(
                                            color: PdfColor.fromInt(0xFFFFD33A),
                                            borderRadius: pw.BorderRadius.all(pw.Radius.circular(2.0)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    pw.Positioned(
                                      left: 24.9,
                                      top: 25.4,
                                      child: pw.Transform.rotate(
                                        angle: 0.50,
                                        child: pw.Container(
                                          width: 10.0,
                                          height: 3.8,
                                          decoration: const pw.BoxDecoration(
                                            color: PdfColor.fromInt(0xFF2D67FF),
                                            borderRadius: pw.BorderRadius.all(pw.Radius.circular(1.9)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('ScoutAI', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          'SCOUTAI',
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.5,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('ScoutAI Football', style: const pw.TextStyle(fontSize: 11.8, color: PdfColors.white)),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: 132,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      border: pw.Border.all(color: PdfColors.blueGrey200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('CONTRACT REF', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                        pw.Text(contractRef, style: const pw.TextStyle(fontSize: 6.5)),
                        pw.SizedBox(height: 3),
                        pw.Text('EFFECTIVE DATE', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                        pw.Text('${txt(draft['startDate'])} to ${txt(draft['endDate'])}', style: const pw.TextStyle(fontSize: 6.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Text(
                'OFFICIAL EMPLOYMENT AGREEMENT',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFD6C28F)),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text('BETWEEN:', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('1. THE CLUB: $clubName, a professional football club under applicable federation regulations.', style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.2)),
            pw.Text('2. THE PLAYER: $playerName (ID: $playerIdLabel), registered for professional participation and contractual obligations.', style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.2)),
            pw.Text('3. THE AGENCY: ScoutAI Agency (legal@scoutai.pro), compliance and digital governance representative.', style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.2)),
            pw.Text('4. THE SCOUTER: ID $scouterId, acting as authorized intermediary.', style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.2)),
            pw.SizedBox(height: 10),
            pw.Text('ARTICLE 1: TERM OF ENGAGEMENT', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(
              '1.1 The term of this contract begins on ${txt(draft['startDate'])} and expires on ${txt(draft['endDate'])}. The player shall remain available for official sporting duties throughout the term under club and federation rules.',
              style: const pw.TextStyle(fontSize: 9.1, lineSpacing: 1.22),
            ),
            pw.SizedBox(height: 8),
            pw.Text('ARTICLE 3: COMPENSATION AND REMUNERATION', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('3.1 Fixed annual remuneration (base): $currency ${_numToText(draft['fixedBaseSalary'])}', style: const pw.TextStyle(fontSize: 9.1)),
            pw.Text('3.2 Signature pre-contract No refund [Prix variable] : prime de signature 0,75 - 1% ($currency ${signaturePrimeMin.toStringAsFixed(2)} to $currency ${signaturePrimeMax.toStringAsFixed(2)})', style: const pw.TextStyle(fontSize: 9.1)),
            pw.Text('3.3 Performance-related bonuses:', style: const pw.TextStyle(fontSize: 9.1)),
            pw.Bullet(text: 'Appearance bonus: $currency ${_numToText(draft['bonusPerAppearance'])}'),
            pw.Bullet(text: 'Goal/Clean sheet bonus: $currency ${_numToText(draft['bonusGoalOrCleanSheet'])}'),
            pw.Bullet(text: 'Team trophy bonus: $currency ${_numToText(draft['bonusTeamTrophy'])}'),
            pw.Text('3.4 Transfer provisions and release clause: $currency ${_numToText(draft['releaseClauseAmount'])}', style: const pw.TextStyle(fontSize: 9.1)),
            pw.Text('3.5 Fees and commissions:', style: const pw.TextStyle(fontSize: 9.1)),
            pw.Bullet(text: 'Fixed contract amount: $currency ${fixedPrice.toStringAsFixed(2)}'),
            pw.Bullet(text: 'Agency commission (tiered estimate): $currency ${tieredCommission.toStringAsFixed(2)}'),
            pw.Bullet(text: '3% on the portion up to EUR 500,000'),
            pw.Bullet(text: '2% on the portion between EUR 500,001 and EUR 2,000,000'),
            pw.Bullet(text: '1% on any portion exceeding EUR 2,000,000'),
            pw.Bullet(text: 'Verification fee: USD 30 (paid by platform)'),
            pw.SizedBox(height: 8),
            pw.Text('Agency Information', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            ...agencyInfo.map((line) => pw.Bullet(text: line)),
            pw.SizedBox(height: 8),
            pw.Text('Agency Clauses', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            ...agencyClauses.map(
              (c) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(c['title']!, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(c['body']!, style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Termination For Cause Clause', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
              child: pw.Text(txt(draft['terminationForCauseText']), style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Professional Clauses', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            ...clauses.map(
              (c) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(c['title']!, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(c['body']!, style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Cadre Juridique Du Contrat Professionnel', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            ...legalArticles.map(
              (c) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(c, style: const pw.TextStyle(fontSize: 9.4, lineSpacing: 1.25)),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Juridical Responsibilities By Party', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            ...partyLegalNotes.map(
              (c) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(c, style: const pw.TextStyle(fontSize: 9.4, lineSpacing: 1.25)),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Player Signature', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(height: 4),
                        playerSig == null ? pw.Text('Pending', style: const pw.TextStyle(fontSize: 9)) : pw.Image(playerSig, height: 52, fit: pw.BoxFit.contain),
                        pw.SizedBox(height: 3),
                        pw.Text('Signed: ${signedByPlayer ? 'Yes' : 'No'}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('Time: ${txt(workflow.contractSignedAt)}', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Scouter Signature', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(height: 4),
                        scouterSig == null ? pw.Text('Pending', style: const pw.TextStyle(fontSize: 9)) : pw.Image(scouterSig, height: 52, fit: pw.BoxFit.contain),
                        pw.SizedBox(height: 3),
                        pw.Text('Signed: ${signedByScouter ? 'Yes' : 'No'}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('Time: ${txt(workflow.scouterSignedAt)}', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('ScoutAI Agency', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(height: 4),
                        agencySigBox,
                        pw.SizedBox(height: 3),
                        pw.Text('Signed: Yes (Digital QR)', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('Time: ${txt(workflow.contractSignedAt)}', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text('Annexes Contractuelles Detaillees', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('Annex A - Barreme financier: details des primes, objectifs, performances collectives et modalites de calcul.', style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2)),
            pw.Text('Annex B - Commission ScoutAI par tranches (3%/2%/1%): base contractuelle, echeancier, et traceabilite de paiement.', style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2)),
            pw.Text('Annex C - Protocole medical: suivi blessure, reprise sportive, controles medicaux et obligations de soins.', style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2)),
            pw.Text('Annex D - Rupture anticipee: faute grave, procedure, indemnite et voies de recours.', style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2)),
            pw.Text('Annex E - Image et media: droits collectifs/individuels, sponsors, reseaux sociaux, interviews.', style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2)),
            pw.Text('Annex F - Ethique et conformite: antidopage, anti corruption, paris sportifs, confidentialite.', style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2)),
            pw.Text('Annex G - Calendrier administratif: homologation ligue, autorisation de travail, enregistrement federation.', style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2)),
            pw.Text('Annex H - Grille disciplinaire: avertissements, amendes, suspension des bonus, procedure de defense.', style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2)),
            pw.SizedBox(height: 5),
            pw.Bullet(text: 'Detail A-H.1: chaque annexe precise responsable, calendrier, format de preuve et mode de validation.'),
            pw.Bullet(text: 'Detail A-H.2: obligations financieres et disciplinaires sont executees uniquement sur base documentaire verifiable.'),
            pw.Bullet(text: 'Detail A-H.3: tout ecart substantiel est traite via procedure contradictoire avec droit de reponse des parties.'),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Text(
                'Annex precedence clause: annexes are binding. In any conflict, mandatory federation and FIFA/TAS compliance rules prevail, then the body of contract, then operational annex guidance.',
                style: const pw.TextStyle(fontSize: 8.7, lineSpacing: 1.2, color: PdfColors.blueGrey800),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Text(
                'By signature, the Parties confirm legal capacity, full understanding of obligations, and acceptance of QR-based digital signature records as admissible evidence of contractual consent.',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
      ),
    );

    final bytes = await doc.save();
    final safe = playerName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final fileName = 'ScoutAI_Contract_$safe.pdf';
    final didWebDownload = await triggerPdfDownload(bytes, fileName);
    if (didWebDownload) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contract PDF downloaded: $fileName'), backgroundColor: AppColors.success),
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
      SnackBar(content: Text('Contract PDF downloaded: $fileName'), backgroundColor: AppColors.success),
    );
  }

  Future<void> _exportContractPdfAfterRefresh() async {
    await _load();
    if (!mounted) return;
    final latestSigned = _workflow?.contractSignedByPlayer == true;
    if (!latestSigned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player signature is still pending. Please try again in a moment.')),
      );
      return;
    }
    await _exportContractPdf();
  }

  @override
  Widget build(BuildContext context) {
    final wf = _workflow ?? const ScouterPlayerWorkflow.empty();
    final playerSigned = wf.contractSignedByPlayer;
    final verificationApproved = wf.verificationStatus == 'verified';
    final fixedPrice = double.tryParse(_fixedPriceCtrl.text.trim()) ?? wf.fixedPrice;
    final currency = _currencyCtrl.text.trim().isEmpty ? 'EUR' : _currencyCtrl.text.trim().toUpperCase();

    return GradientScaffold(
      appBar: AppBar(
        title: const Text(
          'Scouter Contract Editor',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    _animatedIn(
                      index: 0,
                      child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.surf(context).withValues(alpha: 0.88),
                            AppColors.surf2(context).withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.white10,
                            backgroundImage: widget.portraitBytes != null ? MemoryImage(widget.portraitBytes!) : null,
                            child: widget.portraitBytes == null ? const Icon(Icons.person, color: Colors.white70) : null,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.player.displayName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Player ID Number: ${widget.player.playerIdNumber.isEmpty ? '-' : widget.player.playerIdNumber}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                    const SizedBox(height: 12),
                    _animatedIn(
                      index: 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_graph_rounded, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Live total: $currency ${fixedPrice.toStringAsFixed(2)}  |  Agency tiered est.: ${_tieredAgencyCommission(fixedPrice).toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _animatedIn(
                      index: 2,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.today_rounded, size: 16),
                            label: const Text('Today Start'),
                            onPressed: _setTodayAsStart,
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.event_repeat_rounded, size: 16),
                            label: const Text('End +3Y'),
                            onPressed: () => _setEndInYears(3),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.calendar_month_rounded, size: 16),
                            label: const Text('End +5Y'),
                            onPressed: () => _setEndInYears(5),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.schedule_rounded, size: 16),
                            label: const Text('Monthly'),
                            onPressed: () => setState(() => _salaryPeriod = 'monthly'),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.schedule_send_rounded, size: 16),
                            label: const Text('Weekly'),
                            onPressed: () => setState(() => _salaryPeriod = 'weekly'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _animatedIn(
                      index: 3,
                      child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusPill('Verification', wf.verificationStatus),
                        _statusPill('Pre-contract', wf.preContractStatus),
                        _statusPill('Platform Fee', wf.scouterPlatformFeePaid ? 'paid (optional)' : 'optional'),
                        _statusPill('Scouter Signed', wf.scouterSignedContract ? 'yes' : 'pending'),
                        _statusPill('Player Signed', playerSigned ? 'yes' : 'pending'),
                      ],
                    ),
                    ),
                    if (!verificationApproved)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Expert verification must be approved before scouter can sign/pay contract.',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: 14),
                    _animatedIn(
                      index: 4,
                      child: _sectionCard(
                      title: 'Core Contract Terms',
                      subtitle: 'Fill the mandatory terms before drafting or approval.',
                      children: [
                        TextField(
                          controller: _fixedPriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _fieldDecoration(
                            label: 'Fixed Price',
                            hint: 'Type or select amount',
                            prefix: '${_currencySymbol()} ',
                            suffixIcon: IconButton(
                              tooltip: 'Select amount',
                              onPressed: _busy ? null : () => _pickAmount(_fixedPriceCtrl, 'Fixed Price'),
                              icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _clubNameCtrl,
                          decoration: _fieldDecoration(label: 'Club Name'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _intermediaryCtrl,
                          decoration: _fieldDecoration(
                            label: 'Scouter ID',
                            hint: 'Enter your real intermediary ID',
                          ),
                        ),
                      ],
                    ),
                    ),
                    const SizedBox(height: 12),
                    _animatedIn(
                      index: 5,
                      child: _sectionCard(
                      title: 'Dates and Salary Structure',
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _startDateCtrl,
                                readOnly: true,
                                onTap: () => _pickDate(_startDateCtrl, title: 'Select start date'),
                                decoration: _fieldDecoration(
                                  label: 'Start Date',
                                  hint: 'Pick date',
                                ).copyWith(suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18, color: Colors.white70)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _endDateCtrl,
                                readOnly: true,
                                onTap: () => _pickDate(_endDateCtrl, title: 'Select end date'),
                                decoration: _fieldDecoration(
                                  label: 'End Date',
                                  hint: 'Pick date',
                                ).copyWith(suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18, color: Colors.white70)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _currencyCtrl,
                                textCapitalization: TextCapitalization.characters,
                                onChanged: (v) {
                                  final up = v.toUpperCase();
                                  if (v != up) {
                                    _currencyCtrl.value = _currencyCtrl.value.copyWith(
                                      text: up,
                                      selection: TextSelection.collapsed(offset: up.length),
                                    );
                                  }
                                  setState(() {});
                                },
                                decoration: _fieldDecoration(
                                  label: 'Currency',
                                  hint: 'Type (ex: DZD) or select',
                                  suffixIcon: IconButton(
                                    tooltip: 'Select currency',
                                    onPressed: _busy ? null : _pickCurrencyQuick,
                                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _salaryPeriod,
                                items: const [
                                  DropdownMenuItem(value: 'monthly', child: Text('Monthly salary')),
                                  DropdownMenuItem(value: 'weekly', child: Text('Weekly salary')),
                                ],
                                onChanged: _busy ? null : (v) => setState(() => _salaryPeriod = v == 'weekly' ? 'weekly' : 'monthly'),
                                decoration: _fieldDecoration(label: 'Salary Period'),
                                dropdownColor: AppColors.surf(context),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ),
                    const SizedBox(height: 12),
                    _animatedIn(
                      index: 6,
                      child: _sectionCard(
                      title: 'Compensation Breakdown',
                      children: [
                        Row(
                          children: [
                            Expanded(child: _moneyField(_fixedBaseSalaryCtrl, 'Fixed Base Salary')),
                            const SizedBox(width: 8),
                            Expanded(child: _moneyField(_signingFeeCtrl, 'Signing Fee')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _moneyField(_marketValueCtrl, 'Market Value')),
                            const SizedBox(width: 8),
                            Expanded(child: _moneyField(_releaseClauseCtrl, 'Release Clause')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _moneyField(_bonusAppearanceCtrl, 'Bonus / Appearance')),
                            const SizedBox(width: 8),
                            Expanded(child: _moneyField(_bonusGoalCtrl, 'Bonus Goal/Clean Sheet')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _moneyField(_bonusTrophyCtrl, 'Bonus Team Trophy'),
                      ],
                    ),
                    ),
                    const SizedBox(height: 12),
                    _animatedIn(
                      index: 7,
                      child: _sectionCard(
                      title: 'Clauses, Fees and Signatures',
                      children: [
                        TextField(
                          controller: _terminationCtrl,
                          maxLines: 3,
                          decoration: _fieldDecoration(label: 'Termination for Cause Clause'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Agency commission (tiered est.): $currency ${_tieredAgencyCommission(fixedPrice).toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Platform fee payment is optional and available in your profile billing area.',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Expert verification fee: USD 30 (paid by platform, not from this contract).',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _pickScouterSignatureImage,
                              icon: const Icon(Icons.qr_code_2),
                              label: Text(_scouterSignatureBytes == null ? 'Generate My Unique QR Signature' : 'Regenerate My QR Signature'),
                            ),
                            if (_scouterSignatureBytes != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _scouterSignatureFileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_scouterSignatureBytes != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            height: 90,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white24),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Image.memory(_scouterSignatureBytes!, fit: BoxFit.contain),
                          ),
                        ],
                      ],
                    ),
                    ),
                    const SizedBox(height: 12),
                    _animatedIn(
                      index: 8,
                      child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _startNewTestContract,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Start New Test Contract'),
                        ),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _updateScouterDecision('approved'),
                          icon: _busy
                              ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.verified_outlined),
                          label: const Text('Approve Player'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _updateScouterDecision('cancelled'),
                          child: const Text('Cancel'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _updatePreContract(status: 'draft'),
                          child: const Text('Save Draft Pre-Contract'),
                        ),
                        FilledButton(
                          onPressed: _busy || !verificationApproved ? null : () => _updatePreContract(status: 'approved'),
                          child: const Text('Approve + Sign Contract'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _exportContractPdfAfterRefresh,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Export Contract PDF'),
                        ),
                      ],
                    ),
                    ),
                    if (!playerSigned)
                      _animatedIn(
                        index: 9,
                        child: const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Player signature is required before scouter can export contract PDF.',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      ),
                  ],
                ),
    );
  }
}
