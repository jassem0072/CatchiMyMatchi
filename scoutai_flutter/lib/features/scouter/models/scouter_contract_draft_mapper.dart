import 'scouter_contract_draft.dart';
import 'scouter_contract_draft_dto.dart';

class ScouterContractDraftMapper {
  const ScouterContractDraftMapper._();

  static ScouterContractDraft toEntity(ScouterContractDraftDto dto) {
    return ScouterContractDraft(
      clubName: dto.clubName,
      clubOfficialName: dto.clubOfficialName,
      startDate: dto.startDate,
      endDate: dto.endDate,
      currency: dto.currency,
      salaryPeriod: dto.salaryPeriod,
      fixedBaseSalary: dto.fixedBaseSalary,
      signingOnFee: dto.signingOnFee,
      marketValue: dto.marketValue,
      bonusPerAppearance: dto.bonusPerAppearance,
      bonusGoalOrCleanSheet: dto.bonusGoalOrCleanSheet,
      bonusTeamTrophy: dto.bonusTeamTrophy,
      releaseClauseAmount: dto.releaseClauseAmount,
      terminationForCauseText: dto.terminationForCauseText,
      scouterIntermediaryId: dto.scouterIntermediaryId,
    );
  }

  static ScouterContractDraftDto toDto(ScouterContractDraft entity) {
    return ScouterContractDraftDto(
      clubName: entity.clubName,
      clubOfficialName: entity.clubOfficialName,
      startDate: entity.startDate,
      endDate: entity.endDate,
      currency: entity.currency,
      salaryPeriod: entity.salaryPeriod,
      fixedBaseSalary: entity.fixedBaseSalary,
      signingOnFee: entity.signingOnFee,
      marketValue: entity.marketValue,
      bonusPerAppearance: entity.bonusPerAppearance,
      bonusGoalOrCleanSheet: entity.bonusGoalOrCleanSheet,
      bonusTeamTrophy: entity.bonusTeamTrophy,
      releaseClauseAmount: entity.releaseClauseAmount,
      terminationForCauseText: entity.terminationForCauseText,
      scouterIntermediaryId: entity.scouterIntermediaryId,
    );
  }
}
