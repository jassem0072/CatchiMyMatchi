import '../../../core/network/api_client.dart';
import '../models/scouter.dart';
import '../models/scouter_dto.dart';
import '../models/scouter_mapper.dart';
import '../models/scouter_player.dart';
import '../models/scouter_player_dto.dart';
import '../models/scouter_player_mapper.dart';
import '../models/scouter_player_workflow.dart';
import '../models/scouter_player_workflow_dto.dart';
import '../models/scouter_player_workflow_mapper.dart';

class ScouterService {
  ScouterService(this._apiClient);

  final ApiClient _apiClient;

  Future<Scouter> getCurrentScouter() async {
    final data = await _apiClient.get('/me');
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid /me payload');
    }
    return ScouterMapper.toEntity(ScouterDto.fromJson(data));
  }

  Future<List<ScouterPlayer>> getFavoritePlayers() async {
    final data = await _apiClient.get('/players');
    if (data is! List) return const <ScouterPlayer>[];

    return data
        .whereType<Map>()
        .map((item) => ScouterPlayerMapper.toEntity(
              ScouterPlayerDto.fromJson(Map<String, dynamic>.from(item)),
            ))
        .where((player) => player.isFavorite)
        .toList();
  }

  Future<ScouterPlayerWorkflow?> getScouterPlayerWorkflow(String playerId) async {
    final safePlayerId = playerId.trim();
    if (safePlayerId.isEmpty) return null;

    final adminWorkflow = await _tryFetchAdminWorkflow(safePlayerId);
    if (adminWorkflow != null) {
      return ScouterPlayerWorkflowMapper.toEntity(
        ScouterPlayerWorkflowDto.fromJson(adminWorkflow),
      );
    }

    final dashboardWorkflow = await _tryFetchDashboardWorkflow(safePlayerId);
    if (dashboardWorkflow == null) return null;

    return ScouterPlayerWorkflowMapper.toEntity(
      ScouterPlayerWorkflowDto.fromJson(dashboardWorkflow),
    );
  }

  Future<Map<String, dynamic>?> _tryFetchAdminWorkflow(String playerId) async {
    try {
      final data = await _apiClient.get('/admin/players/$playerId');
      if (data is! Map<String, dynamic>) return null;
      final workflow = data['workflow'];
      if (workflow is Map<String, dynamic>) return workflow;
      if (workflow is Map) return Map<String, dynamic>.from(workflow);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _tryFetchDashboardWorkflow(String playerId) async {
    try {
      final data = await _apiClient.get('/players/$playerId/dashboard');
      if (data is! Map<String, dynamic>) return null;

      final player = data['player'];
      if (player is! Map) return null;

      final adminWorkflow = player['adminWorkflow'];
      if (adminWorkflow is Map<String, dynamic>) return adminWorkflow;
      if (adminWorkflow is Map) return Map<String, dynamic>.from(adminWorkflow);
      return null;
    } catch (_) {
      return null;
    }
  }
}
