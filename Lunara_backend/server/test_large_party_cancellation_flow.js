const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const { v4: uuidv4 } = require('uuid');

async function runTests() {
    console.log('--- Starting Large Party Cancellation & Admin Refund Integration Tests ---');
    const { default: sequelize } = require('./dist/config/database');
    await sequelize.authenticate();
    console.log('Database connected successfully.');

    const {
        User,
        Venue,
        Booking,
        LargePartyCancellationRequest,
        LargePartyCancellationStatus,
        LargePartyRefundMethod,
        SmartWallet,
    } = require('./dist/models');
    const { LargePartyCancellationService } = require('./dist/services/LargePartyCancellationService');

    // Sync models
    console.log('Syncing LargePartyCancellationRequest model...');
    await LargePartyCancellationRequest.sync({ alter: true });
    console.log('LargePartyCancellationRequest model synced.');

    // Create test host & admin
    const hostUser = await User.create({
        id: uuidv4(),
        firstName: 'LargeParty',
        lastName: 'Host',
        email: `lphost_${Date.now()}@test.com`,
        phone: `9${Math.floor(100000000 + Math.random() * 900000000)}`,
        dateOfBirth: '1995-01-01',
        passwordHash: 'dummyhash',
        role: 'customer',
        walletBalance: 0,
    });

    const adminUser = await User.create({
        id: uuidv4(),
        firstName: 'Lunara',
        lastName: 'Admin',
        email: `lpadmin_${Date.now()}@test.com`,
        phone: `9${Math.floor(100000000 + Math.random() * 900000000)}`,
        dateOfBirth: '1990-01-01',
        passwordHash: 'dummyhash',
        role: 'admin',
    });

    const otherUser = await User.create({
        id: uuidv4(),
        firstName: 'Imposter',
        lastName: 'User',
        email: `imposter_${Date.now()}@test.com`,
        phone: `9${Math.floor(100000000 + Math.random() * 900000000)}`,
        dateOfBirth: '1998-01-01',
        passwordHash: 'dummyhash',
        role: 'customer',
    });

    let venue = await Venue.findOne();
    if (!venue) {
        venue = await Venue.create({
            id: uuidv4(),
            ownerId: adminUser.id,
            name: 'Sky Lounge High Spirits',
            slug: `sky-lounge-${Date.now()}`,
            category: 'nightclub',
            city: 'Mumbai',
            state: 'Maharashtra',
            postalCode: '400050',
            phone: '9876543210',
            addressLine1: 'Bandra West',
        });
    }

    // =========================================================================
    // TEST 1: WALLET REFUND FLOW (80% POLICY)
    // =========================================================================
    console.log('\n========================================');
    console.log('TEST 1: WALLET REFUND FLOW (80% POLICY)');
    console.log('========================================');

    const booking1 = await Booking.create({
        id: uuidv4(),
        userId: hostUser.id,
        venueId: venue.id,
        isLargePartyRequest: true,
        numberOfGuests: 30,
        partySubject: 'College Reunion 2026',
        bookingDate: new Date(Date.now() + 86400000 * 5),
        startTime: '21:00',
        totalAmount: 10000,
        adminPaymentAmount: 10000,
        commissionAmount: 1000,
        status: 'confirmed',
        paymentStatus: 'paid',
        adminApprovalStatus: 'payment_done',
    });

    console.log(`Large Party 1 created: ${booking1.id}, Amount: ₹10,000, Status: confirmed`);

    // 1. Host requests cancellation
    const cancelRes1 = await LargePartyCancellationService.requestCancellation({
        bookingId: booking1.id,
        userId: hostUser.id,
        reason: 'Medical emergency in host family',
        reasonDetails: 'Need to travel urgently',
        upiId: 'hostuser@okhdfcbank',
        mobileNumber: '9876543210',
    });

    console.log('Host cancel request result:', cancelRes1.message);
    if (!cancelRes1.success) throw new Error(`Cancel request failed: ${cancelRes1.message}`);

    const reqId1 = cancelRes1.data.id;
    console.log(`Cancellation ID: ${reqId1}, Status: ${cancelRes1.data.status}`);

    // 2. Admin retrieves queue & detail
    const queueRes = await LargePartyCancellationService.getAdminCancellations({ status: LargePartyCancellationStatus.PENDING_ADMIN_REVIEW });
    console.log(`Admin queue total pending requests: ${queueRes.pagination.total}`);

    const detailRes = await LargePartyCancellationService.getAdminCancellationDetail(reqId1);
    console.log(`Detail precalculated 80% policy: Refund ₹${detailRes.data.policyPreviews.find(p => p.percentage === 80).refundAmount}, Non-refundable: ₹${detailRes.data.policyPreviews.find(p => p.percentage === 80).nonRefundableAmount}`);

    // 3. Admin approves with 80% Wallet Refund
    const approveRes1 = await LargePartyCancellationService.adminApproveCancellation({
        requestId: reqId1,
        adminUserId: adminUser.id,
        refundPercentage: 80,
        refundMethod: LargePartyRefundMethod.WALLET,
        adminNotes: 'Approved per medical policy',
    });

    console.log('Approve result:', approveRes1.message);
    if (!approveRes1.success) throw new Error(`Approve failed: ${approveRes1.message}`);

    // Verify wallet balance
    const updatedHost1 = await User.findByPk(hostUser.id);
    console.log(`Host Wallet Balance after 80% refund: ₹${updatedHost1.walletBalance} (expected: 8000)`);
    if (Number(updatedHost1.walletBalance) !== 8000) {
        throw new Error(`Expected host wallet balance 8000, got ${updatedHost1.walletBalance}`);
    }

    const updatedBooking1 = await Booking.findByPk(booking1.id);
    console.log(`Booking status after approval: ${updatedBooking1.status} (expected: cancelled)`);
    if (updatedBooking1.status !== 'cancelled') {
        throw new Error(`Expected booking status cancelled, got ${updatedBooking1.status}`);
    }

    // =========================================================================
    // TEST 2: MANUAL PAYOUT & "MARK AS PAID" (50% POLICY)
    // =========================================================================
    console.log('\n=================================================');
    console.log('TEST 2: MANUAL PAYOUT & "MARK AS PAID" FLOW');
    console.log('=================================================');

    const booking2 = await Booking.create({
        id: uuidv4(),
        userId: hostUser.id,
        venueId: venue.id,
        isLargePartyRequest: true,
        numberOfGuests: 22,
        partySubject: 'Corporate Tech Meet',
        bookingDate: new Date(Date.now() + 86400000 * 3),
        startTime: '20:00',
        totalAmount: 5000,
        commissionAmount: 500,
        status: 'confirmed',
        paymentStatus: 'paid',
        adminApprovalStatus: 'payment_done',
    });

    const cancelRes2 = await LargePartyCancellationService.requestCancellation({
        bookingId: booking2.id,
        userId: hostUser.id,
        reason: 'Office project deadline rescheduled',
        accountHolderName: 'Large Party Host',
        accountNumber: '123456789012',
        ifscCode: 'HDFC0001234',
        mobileNumber: '9876543210',
    });

    const reqId2 = cancelRes2.data.id;

    // Admin approves with MANUAL_PAYOUT (50% = ₹2,500)
    const approveRes2 = await LargePartyCancellationService.adminApproveCancellation({
        requestId: reqId2,
        adminUserId: adminUser.id,
        refundPercentage: 50,
        refundMethod: LargePartyRefundMethod.MANUAL_PAYOUT,
        adminNotes: '50% manual payout approved',
    });

    console.log(`Approval 2 result: ${approveRes2.message}, Status: ${approveRes2.data.status}`);
    if (approveRes2.data.status !== LargePartyCancellationStatus.REFUND_PROCESSING) {
        throw new Error(`Expected status REFUND_PROCESSING, got ${approveRes2.data.status}`);
    }

    // Admin marks manual refund as PAID
    const markPaidRes = await LargePartyCancellationService.adminMarkRefundPaid({
        requestId: reqId2,
        adminUserId: adminUser.id,
        paymentReference: 'IMPS_LP_9876543210',
        paymentNotes: 'Settled via Corporate NetBanking',
    });

    console.log(`Mark Paid result: ${markPaidRes.message}, Final Status: ${markPaidRes.data.status}`);
    if (markPaidRes.data.status !== LargePartyCancellationStatus.COMPLETED) {
        throw new Error(`Expected status COMPLETED, got ${markPaidRes.data.status}`);
    }

    // =========================================================================
    // TEST 3: ADMIN REJECTION PATH
    // =========================================================================
    console.log('\n========================================');
    console.log('TEST 3: ADMIN REJECTION PATH');
    console.log('========================================');

    const booking3 = await Booking.create({
        id: uuidv4(),
        userId: hostUser.id,
        venueId: venue.id,
        isLargePartyRequest: true,
        numberOfGuests: 25,
        partySubject: 'Late Night Bash',
        bookingDate: new Date(Date.now() + 86400000 * 2),
        startTime: '22:00',
        totalAmount: 6000,
        commissionAmount: 600,
        status: 'confirmed',
        paymentStatus: 'paid',
        adminApprovalStatus: 'payment_done',
    });

    const cancelRes3 = await LargePartyCancellationService.requestCancellation({
        bookingId: booking3.id,
        userId: hostUser.id,
        reason: 'Change of mind',
    });

    const reqId3 = cancelRes3.data.id;

    // Admin rejects cancellation
    const rejectRes = await LargePartyCancellationService.adminRejectCancellation({
        requestId: reqId3,
        adminUserId: adminUser.id,
        rejectionReason: 'Cancellation requested less than 48 hours before the event violates standard policy',
    });

    console.log(`Reject result: ${rejectRes.message}, Status: ${rejectRes.data.status}`);
    if (rejectRes.data.status !== LargePartyCancellationStatus.REJECTED) {
        throw new Error(`Expected status REJECTED, got ${rejectRes.data.status}`);
    }

    const updatedBooking3 = await Booking.findByPk(booking3.id);
    console.log(`Booking 3 status after rejection: ${updatedBooking3.status} (expected: confirmed)`);
    if (updatedBooking3.status !== 'confirmed') {
        throw new Error(`Expected booking 3 status confirmed, got ${updatedBooking3.status}`);
    }

    // =========================================================================
    // TEST 4: SECURITY & VALIDATION PATHS
    // =========================================================================
    console.log('\n========================================');
    console.log('TEST 4: SECURITY & VALIDATION PATHS');
    console.log('========================================');

    // 1. Non-owner cannot cancel
    const imposterCancel = await LargePartyCancellationService.requestCancellation({
        bookingId: booking3.id,
        userId: otherUser.id,
        reason: 'Trying to cancel someone elses party',
    });
    console.log(`Imposter cancel attempt: ${imposterCancel.message} (success: ${imposterCancel.success})`);
    if (imposterCancel.success) throw new Error('Imposter should not be able to cancel');

    // 2. Cannot cancel non-large party
    const smallBooking = await Booking.create({
        id: uuidv4(),
        userId: hostUser.id,
        venueId: venue.id,
        isLargePartyRequest: false,
        numberOfGuests: 4,
        bookingDate: new Date(Date.now() + 86400000 * 2),
        startTime: '19:00',
        totalAmount: 1500,
        commissionAmount: 150,
        status: 'confirmed',
        paymentStatus: 'paid',
    });

    const smallCancel = await LargePartyCancellationService.requestCancellation({
        bookingId: smallBooking.id,
        userId: hostUser.id,
        reason: 'Small booking cancellation attempt',
    });
    console.log(`Small booking cancel attempt: ${smallCancel.message} (success: ${smallCancel.success})`);
    if (smallCancel.success) throw new Error('Small booking should not be allowed through large party cancellation');

    console.log('\n🎉 ALL LARGE PARTY CANCELLATION & REFUND TESTS PASSED SUCCESSFULLY!');
}

runTests().then(() => {
    process.exit(0);
}).catch(err => {
    console.error('❌ Test failed:', err);
    process.exit(1);
});
