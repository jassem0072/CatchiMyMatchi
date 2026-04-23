class ScouterContractDraftDto {
  const ScouterContractDraftDto({
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

  const ScouterContractDraftDto.empty()
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

  factory ScouterContractDraftDto.fromJson(Map<String, dynamic> json) {
    final salaryPeriod = (json['salaryPeriod'] ?? 'monthly').toString().toLowerCase();

    return ScouterContractDraftDto(
      clubName: (json['clubName'] ?? '').toString(),
      clubOfficialName: (json['clubOfficialName'] ?? json['clubName'] ?? '').toString(),
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? '').toString(),
      currency: (json['currency'] ?? 'EUR').toString().toUpperCase(),
      salaryPeriod: salaryPeriod == 'weekly' ? 'weekly' : 'monthly',
      fixedBaseSalary: _toDouble(json['fixedBaseSalary']),
      signingOnFee: _toDouble(json['signingOnFee']),
      marketValue: _toDouble(json['marketValue']),
      bonusPerAppearance: _toDouble(json['bonusPerAppearance']),
      bonusGoalOrCleanSheet: _toDouble(json['bonusGoalOrCleanSheet']),
      bonusTeamTrophy: _toDouble(json['bonusTeamTrophy']),
      releaseClauseAmount: _toDouble(json['releaseClauseAmount']),
      terminationForCauseText: (json['terminationForCauseText'] ?? '').toString(),
      scouterIntermediaryId: (json['scouterIntermediaryId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'clubName': clubName,
      'clubOfficialName': clubOfficialName,
      'startDate': startDate,
      'endDate': endDate,
      'currency': currency,
      'salaryPeriod': salaryPeriod,
      'fixedBaseSalary': fixedBaseSalary,
      'signingOnFee': signingOnFee,
      'marketValue': marketValue,
      'bonusPerAppearance': bonusPerAppearance,
      'bonusGoalOrCleanSheet': bonusGoalOrCleanSheet,
      'bonusTeamTrophy': bonusTeamTrophy,
      'releaseClauseAmount': releaseClauseAmount,
      'terminationForCauseText': terminationForCauseText,
      'scouterIntermediaryId': scouterIntermediaryId,
    };
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
