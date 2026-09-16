import 'package:flutter_test/flutter_test.dart';
import 'package:lunara_app/models/user.dart';
import 'package:lunara_app/models/plan_status.dart';

void main() {
  group('User Model - Hide Profile & Visibility Parsing Tests', () {
    test('User with showMeInMatching: true should have invisibleMode: false', () {
      final user = User.fromJson({
        'id': 'test-user-1',
        'firstName': 'John',
        'lastName': 'Doe',
        'email': 'john@example.com',
        'role': 'CUSTOMER',
        'preferences': {
          'showMeInMatching': true,
          'invisibleMode': false,
        },
      });

      expect(user.showMeInMatching, isTrue);
      expect(user.invisibleMode, isFalse);
    });

    test('User with showMeInMatching: false should have invisibleMode: true', () {
      final user = User.fromJson({
        'id': 'test-user-2',
        'firstName': 'Jane',
        'lastName': 'Doe',
        'email': 'jane@example.com',
        'role': 'CUSTOMER',
        'preferences': {
          'showMeInMatching': false,
        },
      });

      expect(user.showMeInMatching, isFalse);
      expect(user.invisibleMode, isTrue);
    });

    test('User with invisibleMode: true should have showMeInMatching: false', () {
      final user = User.fromJson({
        'id': 'test-user-3',
        'firstName': 'Alex',
        'lastName': 'Smith',
        'email': 'alex@example.com',
        'role': 'CUSTOMER',
        'preferences': {
          'invisibleMode': true,
        },
      });

      expect(user.showMeInMatching, isFalse);
      expect(user.invisibleMode, isTrue);
    });

    test('copyWith properly updates showMeInMatching and invisibleMode', () {
      final user = User.fromJson({
        'id': 'test-user-4',
        'firstName': 'Sam',
        'lastName': 'Wilson',
        'email': 'sam@example.com',
        'role': 'CUSTOMER',
        'preferences': {
          'showMeInMatching': true,
        },
      });

      final updated = user.copyWith(
        showMeInMatching: false,
        invisibleMode: true,
      );

      expect(updated.showMeInMatching, isFalse);
      expect(updated.invisibleMode, isTrue);
    });
  });

  group('PlanStatus & VIP Entitlements Tests', () {
    test('Free tier should not have hasHideProfile', () {
      final plan = PlanStatus.fromJson({
        'tier': 'FREE',
        'status': 'ACTIVE',
        'hasHideProfile': false,
      });

      expect(plan.hasHideProfile, isFalse);
    });

    test('PLUS tier should have hasHideProfile enabled by default', () {
      final plan = PlanStatus.fromJson({
        'tier': 'PLUS',
        'status': 'ACTIVE',
      });

      expect(plan.hasHideProfile, isTrue);
    });

    test('PRO and ELITE tiers should have hasHideProfile enabled', () {
      final proPlan = PlanStatus.fromJson({
        'tier': 'PRO',
        'status': 'ACTIVE',
      });
      final elitePlan = PlanStatus.fromJson({
        'tier': 'ELITE',
        'status': 'ACTIVE',
      });

      expect(proPlan.hasHideProfile, isTrue);
      expect(elitePlan.hasHideProfile, isTrue);
    });

    test('Custom package with hasHideProfile: true should enable feature', () {
      final customPlan = PlanStatus.fromJson({
        'tier': 'BASIC',
        'status': 'ACTIVE',
        'hasHideProfile': true,
      });

      expect(customPlan.hasHideProfile, isTrue);
    });
  });
}
