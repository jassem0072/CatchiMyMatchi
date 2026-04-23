import 'scouter_contract_draft_dto.dart';

class ScouterPlayerWorkflowDto {
  const ScouterPlayerWorkflowDto({
    required this.verificationStatus,
    required this.preContractStatus,
    required this.scouterPlatformFeePaid,
    required this.scouterSignedContract,
    required this.contractSignedByPlayer,
    required this.fixedPrice,
    required this.contractSignedAt,
    required this.scouterSignedAt,
    required this.playerSignatureImageBase64,
    required this.playerSignatureImageContentType,
    required this.playerSignatureImageFileName,
    required this.scouterSignatureImageBase64,
    required this.scouterSignatureImageContentType,
    required this.scouterSignatureImageFileName,
    required this.contractDraft,
  });

  const ScouterPlayerWorkflowDto.empty()
      : verificationStatus = 'not_requested',
        preContractStatus = 'none',
        scouterPlatformFeePaid = false,
        scouterSignedContract = false,
        contractSignedByPlayer = false,
        fixedPrice = 0,
        contractSignedAt = '',
        scouterSignedAt = '',
        playerSignatureImageBase64 = '',
        playerSignatureImageContentType = '',
        playerSignatureImageFileName = '',
        scouterSignatureImageBase64 = '',
        scouterSignatureImageContentType = '',
        scouterSignatureImageFileName = '',
        contractDraft = const ScouterContractDraftDto.empty();

  final String verificationStatus;
  final String preContractStatus;
  final bool scouterPlatformFeePaid;
  final bool scouterSignedContract;
  final bool contractSignedByPlayer;
  final double fixedPrice;
  final String contractSignedAt;
  final String scouterSignedAt;
  final String playerSignatureImageBase64;
  final String playerSignatureImageContentType;
  final String playerSignatureImageFileName;
  final String scouterSignatureImageBase64;
  final String scouterSignatureImageContentType;
  final String scouterSignatureImageFileName;
  final ScouterContractDraftDto contractDraft;

  factory ScouterPlayerWorkflowDto.fromJson(Map<String, dynamic> json) {
    final draftJson = json['contractDraft'];

    return ScouterPlayerWorkflowDto(
      verificationStatus: (json['verificationStatus'] ?? 'not_requested').toString(),
      preContractStatus: (json['preContractStatus'] ?? 'none').toString(),
      scouterPlatformFeePaid: _toBool(json['scouterPlatformFeePaid']),
      scouterSignedContract: _toBool(json['scouterSignedContract']),
      contractSignedByPlayer: _toBool(json['contractSignedByPlayer']),
      fixedPrice: _toDouble(json['fixedPrice']),
      contractSignedAt: (json['contractSignedAt'] ?? '').toString(),
      scouterSignedAt: (json['scouterSignedAt'] ?? '').toString(),
      playerSignatureImageBase64: (json['playerSignatureImageBase64'] ?? '').toString(),
        playerSignatureImageContentType: (json['playerSignatureImageContentType'] ?? '').toString(),
        playerSignatureImageFileName: (json['playerSignatureImageFileName'] ?? '').toString(),
      scouterSignatureImageBase64: (json['scouterSignatureImageBase64'] ?? '').toString(),
        scouterSignatureImageContentType: (json['scouterSignatureImageContentType'] ?? '').toString(),
        scouterSignatureImageFileName: (json['scouterSignatureImageFileName'] ?? '').toString(),
      contractDraft: draftJson is Map<String, dynamic>
          ? ScouterContractDraftDto.fromJson(draftJson)
          : draftJson is Map
              ? ScouterContractDraftDto.fromJson(Map<String, dynamic>.from(draftJson))
              : const ScouterContractDraftDto.empty(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'verificationStatus': verificationStatus,
      'preContractStatus': preContractStatus,
      'scouterPlatformFeePaid': scouterPlatformFeePaid,
      'scouterSignedContract': scouterSignedContract,
      'contractSignedByPlayer': contractSignedByPlayer,
      'fixedPrice': fixedPrice,
      'contractSignedAt': contractSignedAt,
      'scouterSignedAt': scouterSignedAt,
      'playerSignatureImageBase64': playerSignatureImageBase64,
      'playerSignatureImageContentType': playerSignatureImageContentType,
      'playerSignatureImageFileName': playerSignatureImageFileName,
      'scouterSignatureImageBase64': scouterSignatureImageBase64,
      'scouterSignatureImageContentType': scouterSignatureImageContentType,
      'scouterSignatureImageFileName': scouterSignatureImageFileName,
      'contractDraft': contractDraft.toJson(),
    };
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value?.toString().toLowerCase().trim() ?? '';
    return s == 'true' || s == '1' || s == 'yes';
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
