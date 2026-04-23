import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/player/models/player_dto.dart';

void main() {
  group('PlayerDto.fromJson', () {
    test('parses complete JSON correctly', () {
      final json = <String, dynamic>{
        '_id': 'abc123',
        'displayName': 'John Doe',
        'email': 'john@example.com',
        'position': 'st',
        'nation': 'France',
      };

      final dto = PlayerDto.fromJson(json);
      expect(dto.id, 'abc123');
      expect(dto.displayName, 'John Doe');
      expect(dto.email, 'john@example.com');
      expect(dto.position, 'ST');
      expect(dto.nation, 'France');
    });

    test('uses "id" field when "_id" is absent', () {
      final json = <String, dynamic>{
        'id': 'xyz789',
        'displayName': 'Jane',
        'email': 'jane@test.com',
        'position': 'GK',
        'nation': 'Spain',
      };

      final dto = PlayerDto.fromJson(json);
      expect(dto.id, 'xyz789');
    });

    test('provides defaults for missing fields', () {
      final dto = PlayerDto.fromJson(const <String, dynamic>{});
      expect(dto.id, '');
      expect(dto.displayName, '');
      expect(dto.email, '');
      expect(dto.position, 'CM');
      expect(dto.nation, '');
    });

    test('converts position to uppercase', () {
      final dto = PlayerDto.fromJson(<String, dynamic>{
        'position': 'lw',
      });
      expect(dto.position, 'LW');
    });
  });

  group('PlayerDto.toJson', () {
    test('serializes correctly', () {
      const dto = PlayerDto(
        id: 'p1',
        displayName: 'Test Player',
        email: 'test@test.com',
        position: 'CB',
        nation: 'Germany',
      );

      final json = dto.toJson();
      expect(json['id'], 'p1');
      expect(json['displayName'], 'Test Player');
      expect(json['email'], 'test@test.com');
      expect(json['position'], 'CB');
      expect(json['nation'], 'Germany');
    });
  });
}
