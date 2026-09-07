import 'package:flutter_test/flutter_test.dart';
import 'package:lunara_app/models/vip_entitlement_model.dart';
import 'package:lunara_app/services/subscription_provider.dart';

void main() {
  group('VIP Entitlement Models - Column & Field Validations', () {
    test('PlanEntitlementItem.fromJson parses all fields and handles null/edge types', () {
      final json = {
        'featureKey': 'superlike',
        'name': 'Super Likes',
        'icon': '⭐',
        'includedQuantity': '5',
        'usedQuantity': 2.0,
        'remainingQuantity': 3,
        'progressPercentage': 40,
        'isUnlimited': false,
        'unit': 'per cycle',
        'isLow': true,
      };

      final item = PlanEntitlementItem.fromJson(json);

      expect(item.featureKey, equals('superlike'));
      expect(item.name, equals('Super Likes'));
      expect(item.icon, equals('⭐'));
      expect(item.includedQuantity, equals(5));
      expect(item.usedQuantity, equals(2));
      expect(item.remainingQuantity, equals(3));
      expect(item.progressPercentage, equals(40));
      expect(item.isUnlimited, isFalse);
      expect(item.unit, equals('per cycle'));
      expect(item.isLow, isTrue);
    });

    test('IncludedChecklistItem.fromJson parses properly', () {
      final json = {
        'name': 'Hide Profile',
        'description': 'Browse invisibly',
        'isEnabled': true,
        'icon': '🔒',
      };

      final item = IncludedChecklistItem.fromJson(json);
      expect(item.name, equals('Hide Profile'));
      expect(item.description, equals('Browse invisibly'));
      expect(item.isEnabled, isTrue);
      expect(item.icon, equals('🔒'));
    });

    test('AddonBalanceItem.fromJson parses all quantity columns', () {
      final json = {
        'id': 'addon-123',
        'featureKey': 'backtrack',
        'name': '10 Backtracks Add-on',
        'purchasedQuantity': '10',
        'usedQuantity': 4,
        'remainingQuantity': 6,
      };

      final item = AddonBalanceItem.fromJson(json);
      expect(item.id, equals('addon-123'));
      expect(item.featureKey, equals('backtrack'));
      expect(item.name, equals('10 Backtracks Add-on'));
      expect(item.purchasedQuantity, equals(10));
      expect(item.usedQuantity, equals(4));
      expect(item.remainingQuantity, equals(6));
    });

    test('SubscriptionAddonPackageModel.fromJson parses price, currency, quantity, badge', () {
      final json = {
        'id': 'pkg-abc',
        'name': '+5 Party Plans',
        'featureKey': 'party_creation',
        'quantity': '5',
        'price': '199.00',
        'currency': 'INR',
        'isActive': true,
        'badge': 'EXCLUSIVE',
        'description': 'Host 5 extra parties',
        'displayOrder': 5,
      };

      final pkg = SubscriptionAddonPackageModel.fromJson(json);
      expect(pkg.id, equals('pkg-abc'));
      expect(pkg.name, equals('+5 Party Plans'));
      expect(pkg.featureKey, equals('party_creation'));
      expect(pkg.quantity, equals(5));
      expect(pkg.price, equals(199.0));
      expect(pkg.currency, equals('INR'));
      expect(pkg.isActive, isTrue);
      expect(pkg.badge, equals('EXCLUSIVE'));
      expect(pkg.displayOrder, equals(5));
    });

    test('EntitlementsSummaryModel parses totals including backtracks, partyPlans, superlikes, boosts', () {
      final json = {
        'planTier': 'PLUS',
        'planName': 'Plus VIP',
        'isActive': true,
        'isExpired': false,
        'remainingDays': 25,
        'remainingHours': 600,
        'endDate': '2026-10-01T00:00:00.000Z',
        'planBenefits': [
          {
            'featureKey': 'superlike',
            'name': 'Super Likes',
            'icon': '⭐',
            'includedQuantity': 5,
            'usedQuantity': 1,
            'remainingQuantity': 4,
            'progressPercentage': 20,
            'isUnlimited': false,
            'unit': 'per cycle',
            'isLow': false,
          }
        ],
        'includedFeaturesChecklist': [
          {
            'name': 'See Who Liked You',
            'description': 'Instant matches',
            'isEnabled': true,
            'icon': '👁️',
          }
        ],
        'activeAddons': [
          {
            'featureKey': 'backtrack',
            'name': '+10 Backtracks',
            'purchasedQuantity': 10,
            'usedQuantity': 2,
            'remainingQuantity': 8,
          },
          {
            'featureKey': 'party_creation',
            'name': '+5 Party Plans',
            'purchasedQuantity': 5,
            'usedQuantity': 1,
            'remainingQuantity': 4,
          }
        ],
        'totals': {
          'superlikesAvailable': 4,
          'boostsAvailable': 2,
          'partyPlansAvailable': 7,
          'likesAvailable': 'unlimited',
          'backtracksAvailable': 8,
        },
        'smartSuggestions': [
          {
            'featureKey': 'superlike',
            'title': 'Get more Super Likes',
            'subtitle': 'Stand out more',
            'actionLabel': 'Get Super Likes',
            'addonPackageId': 'addon-pkg-1',
          }
        ],
      };

      final summary = EntitlementsSummaryModel.fromJson(json);

      expect(summary.planTier, equals('PLUS'));
      expect(summary.isActive, isTrue);
      expect(summary.isExpired, isFalse);
      expect(summary.remainingDays, equals(25));
      expect(summary.superlikesAvailable, equals(4));
      expect(summary.boostsAvailable, equals(2));
      expect(summary.partyPlansAvailable, equals(7));
      expect(summary.likesAvailable, equals('unlimited'));
      expect(summary.backtracksAvailable, equals(8));
      expect(summary.planBenefits.length, equals(1));
      expect(summary.activeAddons.length, equals(2));
      expect(summary.smartSuggestions.length, equals(1));
    });

    test('EntitlementsSummaryModel backtracksAvailable falls back to undoAvailable if present', () {
      final json = {
        'totals': {
          'undoAvailable': 15,
        }
      };
      final summary = EntitlementsSummaryModel.fromJson(json);
      expect(summary.backtracksAvailable, equals(15));
    });
  });

  group('VipAction & VipActionValidation enum tests', () {
    test('VipAction contains all required action types', () {
      expect(VipAction.values, contains(VipAction.like));
      expect(VipAction.values, contains(VipAction.superlike));
      expect(VipAction.values, contains(VipAction.boost));
      expect(VipAction.values, contains(VipAction.partyPlan));
      expect(VipAction.values, contains(VipAction.backtrack));
      expect(VipAction.values, contains(VipAction.matchRequest));
    });

    test('VipActionValidation constructs properly', () {
      const val = VipActionValidation(
        allowed: true,
        action: VipAction.superlike,
        limit: 5,
        remaining: 3,
        isUnlimited: false,
      );
      expect(val.allowed, isTrue);
      expect(val.action, equals(VipAction.superlike));
      expect(val.limit, equals(5));
      expect(val.remaining, equals(3));
      expect(val.isUnlimited, isFalse);
    });
  });
}
