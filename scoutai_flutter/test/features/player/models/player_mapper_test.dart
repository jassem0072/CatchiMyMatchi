import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/player/models/player.dart';
import 'package:scoutai/features/player/models/player_dto.dart';
import 'package:scoutai/features/player/models/player_mapper.dart';

void main() {
  group('PlayerMapper.toEntity', () {
    test('maps DTO fields to entity', () {
      const dto = PlayerDto(
        id: 'p1',
        displayName: 'Marcus',
        email: 'marcus@club.com',
        position: 'ST',
        nation: 'England',
      );

      final player = PlayerMapper.toEntity(dto);
      expect(player.id, 'p1');
      expect(player.displayName, 'Marcus');
      expect(player.email, 'marcus@club.com');
      expect(player.position, 'ST');
      expect(player.nation, 'England');
    });

    test('uses email prefix as fallback when displayName is empty', () {
      const dto = PlayerDto(
        id: 'p2',
        displayName: '',
        email: 'johndoe@mail.com',
        position: 'CB',
        nation: 'France',
      );

      final player = PlayerMapper.toEntity(dto);
      expect(player.displayName, 'johndoe');
    });

    test('uses email prefix as fallback when displayName is whitespace', () {
      const dto = PlayerDto(
        id: 'p2',
        displayName: '   ',
        email: 'john@mail.com',
        position: 'CB',
        nation: 'France',
      );

      final player = PlayerMapper.toEntity(dto);
      expect(player.displayName, 'john');
    });

    test('uses "Player" fallback when both displayName and email are empty', () {
      const dto = PlayerDto(
        id: 'p3',
        displayName: '',
        email: '',
        position: 'GK',
        nation: '',
      );

      final player = PlayerMapper.toEntity(dto);
      expect(player.displayName, 'Player');
    });

    test('uses "Player" fallback when email has no @ sign', () {
      const dto = PlayerDto(
        id: 'p4',
        displayName: '',
        email: 'noemail',
        position: 'GK',
        nation: '',
      );

      final player = PlayerMapper.toEntity(dto);
      // email.contains('@') is false, so emailPrefix = ''
      // fallbackName = 'Player'
      expect(player.displayName, 'Player');
    });
  });

  group('PlayerMapper.toDto', () {
    test('maps entity fields to DTO', () {
      const player = Player(
        id: 'p1',
        displayName: 'Test',
        email: 'test@test.com',
        position: 'CM',
        nation: 'Brazil',
      );

      final dto = PlayerMapper.toDto(player);
      expect(dto.id, 'p1');
      expect(dto.displayName, 'Test');
      expect(dto.email, 'test@test.com');
      expect(dto.position, 'CM');
      expect(dto.nation, 'Brazil');
    });
  });
}
