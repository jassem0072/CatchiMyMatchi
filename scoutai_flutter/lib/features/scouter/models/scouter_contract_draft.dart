class ScouterContractDraft {
  const ScouterContractDraft({
    required this.clubName,
    required this.clubOfficialName,
    required this.startDate,
    required this.endDate,
    required this.currency,
    required this.salaryPeriod,
    required this.fixedBaseSalary,
    required this.signingOnFee,
    required this.marketValue,
    required this.bonusPerAppearance,
    required this.bonusGoalOrCleanSheet,
    required this.bonusTeamTrophy,
    required this.releaseClauseAmount,
    required this.terminationForCauseText,
    required this.scouterIntermediaryId,
  });

  const ScouterContractDraft.empty()
      : clubName = '',
        clubOfficialName = '',
        startDate = '',
        endDate = '',
        currency = 'EUR',
        salaryPeriod = 'monthly',
        fixedBaseSalary = 0,
        signingOnFee = 0,
        marketValue = 0,
        bonusPerAppearance = 0,
        bonusGoalOrCleanSheet = 0,
        bonusTeamTrophy = 0,
        releaseClauseAmount = 0,
        terminationForCauseText = '',
        scouterIntermediaryId = '';

  final String clubName;
  final String clubOfficialName;
  final String startDate;
  final String endDate;
  final String currency;
  final String salaryPeriod;
  final double fixedBaseSalary;
  final double signingOnFee;
  final double marketValue;
  final double bonusPerAppearance;
  final double bonusGoalOrCleanSheet;
  final double bonusTeamTrophy;
  final double releaseClauseAmount;
  final String terminationForCauseText;
  final String scouterIntermediaryId;
}
