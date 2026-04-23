import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/analysis/models/analysis_run_request.dart';
import 'package:scoutai/features/analysis/models/analysis_run_request_mapper.dart';
import 'package:scoutai/features/analysis/models/analysis_selection.dart';

void main() {
  group('AnalysisRunRequestMapper.toDto', () {
    test('maps entity to DTO correctly', () {
      const request = AnalysisRunRequest(
        videoId: 'vid1',
        selection: AnalysisSelection(
          t0: 1.5,
          x: 100.0,
          y: 200.0,
          w: 50.0,
          h: 60.0,
        ),
        samplingFps: 8,
      );

      final dto = AnalysisRunRequestMapper.toDto(request);
      expect(dto.videoId, 'vid1');
      expect(dto.samplingFps, 8);
      expect(dto.selection.t0, 1.5);
      expect(dto.selection.x, 100.0);
      expect(dto.selection.y, 200.0);
      expect(dto.selection.w, 50.0);
      expect(dto.selection.h, 60.0);
    });

    test('uses default samplingFps of 4', () {
      const request = AnalysisRunRequest(
        videoId: 'vid2',
        selection: AnalysisSelection(
          t0: 0,
          x: 0,
          y: 0,
          w: 100,
          h: 100,
        ),
      );

      expect(request.samplingFps, 4);
      final dto = AnalysisRunRequestMapper.toDto(request);
      expect(dto.samplingFps, 4);
    });

    test('DTO selection toJson produces correct keys', () {
      const request = AnalysisRunRequest(
        videoId: 'vid3',
        selection: AnalysisSelection(
          t0: 2.0,
          x: 10,
          y: 20,
          w: 30,
          h: 40,
        ),
      );

      final dto = AnalysisRunRequestMapper.toDto(request);
      final json = dto.selection.toJson();
      expect(json['t0'], 2.0);
      expect(json['x'], 10.0);
      expect(json['y'], 20.0);
      expect(json['w'], 30.0);
      expect(json['h'], 40.0);
    });
  });
}
