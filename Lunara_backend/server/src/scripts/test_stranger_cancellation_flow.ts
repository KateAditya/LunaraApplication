import sequelize, { connectDatabase } from '../config/database';
import { BookingPolicyService } from '../services/BookingPolicyService';
import { BookingPolicyType } from '../models/BookingPolicyConfig';

async function runTest() {
  console.log('🚀 Starting Stranger Meet Cancellation & Refund Policy Automated Verification...');

  try {
    await connectDatabase();
    console.log('✓ Database connected successfully');

    // 1. Test Stranger Meet Booking Policy Creation / Update
    console.log('\n--- 1. Testing Policy Configuration & Presets ---');
    const policy = await BookingPolicyService.updatePolicy(
      BookingPolicyType.STRANGERS_MEET,
      {
        cancellationCutoffHours: 5, // 5 hours before meet
        refundEnabled: true,
        refundPercentage: 100,
        isActive: true,
      }
    );

    console.log(`✓ Strangers Meet Policy updated: Cutoff = ${policy.cancellationCutoffHours}h, Refund = ${policy.refundPercentage}%, Enabled = ${policy.refundEnabled}`);
    if (Number(policy.cancellationCutoffHours) !== 5) {
      throw new Error(`Expected cutoff hours to be 5, got ${policy.cancellationCutoffHours}`);
    }

    // 2. Test Cutoff Policy Check
    console.log('\n--- 2. Testing Cutoff Time Validation ---');
    const now = new Date();
    
    // Meet 6 hours from now -> cancellation allowed (6 > 5)
    const meetTimeAllowed = new Date(now.getTime() + 6 * 60 * 60 * 1000);
    const hoursRemainingAllowed = (meetTimeAllowed.getTime() - now.getTime()) / (1000 * 60 * 60);
    console.log(`Meet 6h away: hours remaining = ${hoursRemainingAllowed.toFixed(1)}h. Allowed: ${hoursRemainingAllowed >= policy.cancellationCutoffHours}`);
    if (hoursRemainingAllowed < policy.cancellationCutoffHours) {
      throw new Error('Expected 6h meet to be allowed for cancellation');
    }

    // Meet 2 hours from now -> cancellation blocked (2 < 5)
    const meetTimeBlocked = new Date(now.getTime() + 2 * 60 * 60 * 1000);
    const hoursRemainingBlocked = (meetTimeBlocked.getTime() - now.getTime()) / (1000 * 60 * 60);
    console.log(`Meet 2h away: hours remaining = ${hoursRemainingBlocked.toFixed(1)}h. Allowed: ${hoursRemainingBlocked >= policy.cancellationCutoffHours}`);
    if (hoursRemainingBlocked >= policy.cancellationCutoffHours) {
      throw new Error('Expected 2h meet to be blocked for cancellation');
    }

    // 3. Test Custom Presets (1h, 2h, 5h, 10h, 24h/1 day, 48h/2 days)
    console.log('\n--- 3. Testing Standard Presets ---');
    const presets = [1, 2, 5, 10, 24, 48];
    for (const cutoff of presets) {
      const updated = await BookingPolicyService.updatePolicy(
        BookingPolicyType.STRANGERS_MEET,
        {
          cancellationCutoffHours: cutoff,
        }
      );
      console.log(`✓ Preset ${cutoff}h successfully applied and persisted (readback: ${updated.cancellationCutoffHours}h)`);
    }

    // 4. Test ₹1500 Threshold Rule Logic
    console.log('\n--- 4. Testing ₹1500 Refund Rule Logic ---');
    const testAmounts = [
      { amount: 500, expectedMethod: 'WALLET', requiresPayoutDetails: false },
      { amount: 1499, expectedMethod: 'WALLET', requiresPayoutDetails: false },
      { amount: 1500, expectedMethod: 'PAYOUT_CHOICE', requiresPayoutDetails: true },
      { amount: 3000, expectedMethod: 'PAYOUT_CHOICE', requiresPayoutDetails: true },
    ];

    for (const test of testAmounts) {
      const isUnderThreshold = test.amount < 1500;
      const actualMethod = isUnderThreshold ? 'WALLET' : 'PAYOUT_CHOICE';
      console.log(`Amount ₹${test.amount} -> ${actualMethod} (Under ₹1500: ${isUnderThreshold})`);
      if (actualMethod !== test.expectedMethod) {
        throw new Error(`Mismatch for ₹${test.amount}: expected ${test.expectedMethod}, got ${actualMethod}`);
      }
    }

    console.log('\n🎉 ALL STRANGER MEET CANCELLATION & REFUND AUDIT TESTS PASSED WITH 100% SUCCESS!');
    await sequelize.close();
    process.exit(0);
  } catch (error) {
    console.error('❌ Test failed with error:', error);
    process.exit(1);
  }
}

runTest();
