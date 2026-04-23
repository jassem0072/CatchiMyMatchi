import 'scouter_contract_draft.dart';

class ScouterPlayerWorkflow {
  const ScouterPlayerWorkflow({
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

  const ScouterPlayerWorkflow.empty()
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
        contractDraft = const ScouterContractDraft.empty();

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
  final ScouterContractDraft contractDraft;
}
