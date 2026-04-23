import 'scouter_contract_draft_mapper.dart';
import 'scouter_player_workflow.dart';
import 'scouter_player_workflow_dto.dart';

class ScouterPlayerWorkflowMapper {
  const ScouterPlayerWorkflowMapper._();

  static ScouterPlayerWorkflow toEntity(ScouterPlayerWorkflowDto dto) {
    return ScouterPlayerWorkflow(
      verificationStatus: dto.verificationStatus,
      preContractStatus: dto.preContractStatus,
      scouterPlatformFeePaid: dto.scouterPlatformFeePaid,
      scouterSignedContract: dto.scouterSignedContract,
      contractSignedByPlayer: dto.contractSignedByPlayer,
      fixedPrice: dto.fixedPrice,
      contractSignedAt: dto.contractSignedAt,
      scouterSignedAt: dto.scouterSignedAt,
      playerSignatureImageBase64: dto.playerSignatureImageBase64,
      playerSignatureImageContentType: dto.playerSignatureImageContentType,
      playerSignatureImageFileName: dto.playerSignatureImageFileName,
      scouterSignatureImageBase64: dto.scouterSignatureImageBase64,
      scouterSignatureImageContentType: dto.scouterSignatureImageContentType,
      scouterSignatureImageFileName: dto.scouterSignatureImageFileName,
      contractDraft: ScouterContractDraftMapper.toEntity(dto.contractDraft),
    );
  }

  static ScouterPlayerWorkflowDto toDto(ScouterPlayerWorkflow entity) {
    return ScouterPlayerWorkflowDto(
      verificationStatus: entity.verificationStatus,
      preContractStatus: entity.preContractStatus,
      scouterPlatformFeePaid: entity.scouterPlatformFeePaid,
      scouterSignedContract: entity.scouterSignedContract,
      contractSignedByPlayer: entity.contractSignedByPlayer,
      fixedPrice: entity.fixedPrice,
      contractSignedAt: entity.contractSignedAt,
      scouterSignedAt: entity.scouterSignedAt,
      playerSignatureImageBase64: entity.playerSignatureImageBase64,
      playerSignatureImageContentType: entity.playerSignatureImageContentType,
      playerSignatureImageFileName: entity.playerSignatureImageFileName,
      scouterSignatureImageBase64: entity.scouterSignatureImageBase64,
      scouterSignatureImageContentType: entity.scouterSignatureImageContentType,
      scouterSignatureImageFileName: entity.scouterSignatureImageFileName,
      contractDraft: ScouterContractDraftMapper.toDto(entity.contractDraft),
    );
  }
}
