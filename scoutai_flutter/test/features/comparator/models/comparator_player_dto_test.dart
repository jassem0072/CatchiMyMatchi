import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/comparator/models/comparator_player_dto.dart';

void main() {
  group('ComparatorPlayerDto.fromJson', () {
    test('parses complete JSON correctly', () {
      final json = <String, dynamic>{
        '_id': 'cp1',
        'displayName': 'Leo Messi',
        'email': 'leo@barca.com',
        'position': 'rw',
        'nation': 'Argentina',
        'playerIdNumber': 'PID001',
      };

      final dto = ComparatorPlayerDto.fromJson(json);
      expect(dto.id, 'cp1');
      expect(dto.displayName, 'Leo Messi');
      expect(dto.email, 'leo@barca.com');
      expect(dto.position, 'RW');
      expect(dto.nation, 'Argentina');
      expect(dto.playerIdNumber, 'PID001');
    });

    test('falls back to "id" when "_id" missing', () {
      final json = <String, dynamic>{
        'id': 'cp2',
        'displayName': 'Test',
        'email': 'test@test.com',
      };

      final dto = ComparatorPlayerDto.fromJson(json);
      expect(dto.id, 'cp2');
    });

    test('defaults position to CM uppercase when missing', () {
      final dto = ComparatorPlayerDto.fromJson(const <String, dynamic>{});
      expect(dto.position, 'CM');
    });

    test('provides empty defaults for missing fields', () {
      final dto = ComparatorPlayerDto.fromJson(const <String, dynamic>{});
      expect(dto.id, '');
      expect(dto.displayName, '');
      expect(dto.email, '');
      expect(dto.nation, '');
      expect(dto.playerIdNumber, '');
    });
  });

  group('ComparatorPlayerDto.toJson', () {
    test('serializes all fields', () {
      const dto = ComparatorPlayerDto(
        id: 'cp1',
        displayName: 'Player',
        email: 'p@t.com',
        position: 'GK',
        nation: 'Brazil',
        playerIdNumber: 'PID123',
      );

      final json = dto.toJson();
      expect(json['id'], 'cp1');
      expect(json['displayName'], 'Player');
      expect(json['position'], 'GK');
      expect(json['playerIdNumber'], 'PID123');
    });
  });
}
