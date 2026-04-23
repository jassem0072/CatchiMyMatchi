import 'package:flutter_test/flutter_test.dart';
import 'package:scoutai/features/scouter/models/scouter_dto.dart';

void main() {
  group('ScouterDto.fromJson', () {
    test('parses complete JSON correctly', () {
      final json = <String, dynamic>{
        '_id': 's1',
        'displayName': 'John Scout',
        'email': 'john@scout.com',
        'role': 'scouter',
        'nation': 'England',
        'tier': 'premium',
        'verified': true,
        'isPremium': true,
      };

      final dto = ScouterDto.fromJson(json);
      expect(dto.id, 's1');
      expect(dto.displayName, 'John Scout');
      expect(dto.email, 'john@scout.com');
      expect(dto.role, 'scouter');
      expect(dto.nation, 'England');
      expect(dto.subscriptionTier, 'premium');
      expect(dto.isVerified, true);
      expect(dto.isPremium, true);
    });

    test('uses fallback field names', () {
      final json = <String, dynamic>{
        'id': 's2',
        'displayName': 'Scout B',
        'email': 'b@test.com',
        'role': 'admin',
        'nation': 'Spain',
        'subscriptionTier': 'free',
        'isVerified': false,
        'upgraded': true,
      };

      final dto = ScouterDto.fromJson(json);
      expect(dto.id, 's2');
      expect(dto.subscriptionTier, 'free');
      expect(dto.isVerified, false);
      expect(dto.isPremium, true);
    });

    test('defaults for missing fields', () {
      final dto = ScouterDto.fromJson(const <String, dynamic>{});
      expect(dto.id, '');
      expect(dto.displayName, '');
      expect(dto.email, '');
      expect(dto.role, 'scouter');
      expect(dto.nation, '');
      expect(dto.subscriptionTier, '');
      expect(dto.isVerified, false);
      expect(dto.isPremium, false);
    });

    test('_toBool handles various truthy values', () {
      // numeric 1
      var dto = ScouterDto.fromJson(<String, dynamic>{'verified': 1});
      expect(dto.isVerified, true);

      // string "true"
      dto = ScouterDto.fromJson(<String, dynamic>{'verified': 'true'});
      expect(dto.isVerified, true);

      // string "yes"
      dto = ScouterDto.fromJson(<String, dynamic>{'verified': 'yes'});
      expect(dto.isVerified, true);

      // string "1"
      dto = ScouterDto.fromJson(<String, dynamic>{'verified': '1'});
      expect(dto.isVerified, true);

      // numeric 0
      dto = ScouterDto.fromJson(<String, dynamic>{'verified': 0});
      expect(dto.isVerified, false);

      // null
      dto = ScouterDto.fromJson(<String, dynamic>{'verified': null});
      expect(dto.isVerified, false);
    });
  });

  group('ScouterDto.toJson', () {
    test('serializes all fields', () {
      const dto = ScouterDto(
        id: 's1',
        displayName: 'Scout',
        email: 'scout@test.com',
        role: 'scouter',
        nation: 'France',
        subscriptionTier: 'pro',
        isVerified: true,
        isPremium: false,
      );

      final json = dto.toJson();
      expect(json['id'], 's1');
      expect(json['displayName'], 'Scout');
      expect(json['email'], 'scout@test.com');
      expect(json['role'], 'scouter');
      expect(json['nation'], 'France');
      expect(json['subscriptionTier'], 'pro');
      expect(json['isVerified'], true);
      expect(json['isPremium'], false);
    });
  });
}
