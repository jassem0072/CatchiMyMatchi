import '../models/player_analysis.dart';

const mockAnalyses = <PlayerAnalysis>[
  PlayerAnalysis(
    id: 'a1',
    playerName: 'Marcus Rashford',
    playerNumber: 10,
    matchName: 'Man Utd vs Liverpool • Oct 24',
    distanceKm: 10.4,
    maxSpeedKmh: 34.2,
    sprints: 22,
    status: AnalysisStatus.done,
  ),
  PlayerAnalysis(
    id: 'a2',
    playerName: 'Kevin De Bruyne',
    playerNumber: 17,
    matchName: 'Man City vs Arsenal • Oct 22',
    distanceKm: 9.6,
    maxSpeedKmh: 32.1,
    sprints: 18,
    status: AnalysisStatus.processing,
    progress: 0.68,
  ),
  PlayerAnalysis(
    id: 'a3',
    playerName: 'Bukayo Saka',
    playerNumber: 7,
    matchName: 'Arsenal vs Liverpool • Oct 21',
    distanceKm: 9.8,
    maxSpeedKmh: 32.8,
    sprints: 29,
    status: AnalysisStatus.done,
  ),
];
