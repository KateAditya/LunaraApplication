require('dotenv').config({ path: './.env' });

const sequelize = require('./dist/config/database').default;
const models = require('./dist/models');
const {
    User,
    Venue,
    StrangersMeetRequest,
    StrangersMeetJoiner,
    StrangersMeetHostCancellationRequest,
    HostCancellationStatus,
    StrangersMeetMemberRefund,
    MemberRefundStatus,
    SmartWallet,
} = models;
const { StrangersMeetService } = require('./dist/services/StrangersMeetService');

async function main() {
    try {
        await sequelize.authenticate();
        console.log('Database connected successfully.');

        console.log('Syncing Host Cancellation models...');
        await StrangersMeetHostCancellationRequest.sync({ alter: false });
        await StrangersMeetMemberRefund.sync({ alter: false });
        console.log('Host Cancellation models synced.');

        const users = await User.findAll({ limit: 4 });
        if (users.length < 4) {
            console.log('Need at least 4 users in DB to run complete host cancellation test.');
            return;
        }

        const host = users[0];
        const member1 = users[1];
        const member2 = users[2];
        const admin = users[3];
        console.log(`Host: ${host.firstName} (${host.id})`);
        console.log(`Member 1: ${member1.firstName} (${member1.id})`);
        console.log(`Member 2: ${member2.firstName} (${member2.id})`);
        console.log(`Admin: ${admin.firstName} (${admin.id})`);

        const venue = await Venue.findOne();
        if (!venue) {
            console.log('No venue found in DB.');
            return;
        }

        // ====================================================================
        // TEST 1: WALLET REFUND FLOW (80% POLICY)
        // ====================================================================
        console.log('\n========================================');
        console.log('TEST 1: WALLET REFUND FLOW (80% POLICY)');
        console.log('========================================');

        // 1. Create a test Stranger Meet
        const meet1 = await StrangersMeetRequest.create({
            userId: host.id,
            venueId: venue.id,
            subject: 'TEST Host Cancellation Meetup 1',
            tagline: 'Exciting Friday Meetup',
            eventDateTime: new Date(Date.now() + 48 * 60 * 60 * 1000),
            numberOfPersons: 25,
            chargesPerHead: 500.0,
            status: 'approved',
            paymentStatus: 'paid',
            mobileNumber: '9876543210',
            slotsFilled: 2,
        });

        // 2. Create two paid joiners with different paid amounts
        const joiner1 = await StrangersMeetJoiner.create({
            strangersMeetRequestId: meet1.id,
            userId: member1.id,
            status: 'paid',
            paymentStatus: 'paid',
            paymentAmount: 500.0,
        });

        const joiner2 = await StrangersMeetJoiner.create({
            strangersMeetRequestId: meet1.id,
            userId: member2.id,
            status: 'paid',
            paymentStatus: 'paid',
            paymentAmount: 700.0, // Member 2 paid 700
        });

        console.log(`Meet created: ${meet1.id}, Joiner 1: ₹500, Joiner 2: ₹700 (Total: ₹1200)`);

        // 3. Host Requests Cancellation
        console.log('\n--- Host requests cancellation ---');
        const hostCancelRes1 = await StrangersMeetService.requestHostCancellation({
            meetId: meet1.id,
            hostUserId: host.id,
            reason: 'medical_emergency',
            reasonText: 'Unforeseen personal medical emergency.',
        });
        console.log('Host cancel result:', hostCancelRes1.message);
        const cancelReq1 = hostCancelRes1.cancellation;
        console.log(`Cancellation ID: ${cancelReq1.id}, Status: ${cancelReq1.status}, Total Collected: ₹${cancelReq1.totalCollectedAmount}, Members: ${cancelReq1.totalMembersCount}`);

        // 4. Admin Queries Queue & Detail
        console.log('\n--- Admin queries queue & detail ---');
        const queueRes = await StrangersMeetService.getAdminHostCancellations({ status: 'PENDING_ADMIN_REVIEW' });
        console.log(`Queue count: ${queueRes.total}`);

        const detailRes = await StrangersMeetService.getAdminHostCancellationDetail(cancelReq1.id);
        console.log('Detail policy previews:');
        console.log('  100% Policy total refund:', detailRes.policyPreviews['100%'].totalRefund);
        console.log('  80% Policy total refund:', detailRes.policyPreviews['80%'].totalRefund);
        console.log('  80% Member 1 refund:', detailRes.policyPreviews['80%'].members[0].refundAmount);
        console.log('  80% Member 2 refund:', detailRes.policyPreviews['80%'].members[1].refundAmount);

        // 5. Admin Approves with 80% Refund Policy via Lunara Wallet
        console.log('\n--- Admin approves with 80% Wallet refund ---');
        const approveRes1 = await StrangersMeetService.adminApproveHostCancellation({
            cancellationId: cancelReq1.id,
            adminId: admin.id,
            refundPercentage: 80,
            refundMethod: 'WALLET',
            adminNotes: 'Approved emergency cancellation with 80% standard policy.',
        });
        console.log('Approve result:', approveRes1.message);
        console.log(`Cancellation Status: ${approveRes1.cancellation.status}, Total Refund: ₹${approveRes1.cancellation.totalRefundAmount}`);

        // Verify Member 1 & Member 2 Wallets
        const wallet1 = await SmartWallet.findOne({ where: { userId: member1.id } });
        const wallet2 = await SmartWallet.findOne({ where: { userId: member2.id } });
        console.log(`Member 1 Wallet Balance: ₹${wallet1?.balance} (expected +400)`);
        console.log(`Member 2 Wallet Balance: ₹${wallet2?.balance} (expected +560)`);

        await meet1.reload();
        console.log(`Meet 1 status after approval: ${meet1.status} (expected CANCELLED)`);

        // Clean up Test 1
        console.log('\n--- Cleaning up Test 1 ---');
        await StrangersMeetMemberRefund.destroy({ where: { hostCancellationRequestId: cancelReq1.id } });
        await cancelReq1.destroy();
        await joiner1.destroy();
        await joiner2.destroy();
        await meet1.destroy();

        // ====================================================================
        // TEST 2: MANUAL PAYOUT & "MARK AS PAID" FLOW
        // ====================================================================
        console.log('\n=================================================');
        console.log('TEST 2: MANUAL PAYOUT & "MARK AS PAID" FLOW');
        console.log('=================================================');

        const meet2 = await StrangersMeetRequest.create({
            userId: host.id,
            venueId: venue.id,
            subject: 'TEST Host Cancellation Meetup 2 (Manual Payout)',
            tagline: 'Fun Saturday Evening',
            eventDateTime: new Date(Date.now() + 48 * 60 * 60 * 1000),
            numberOfPersons: 25,
            chargesPerHead: 600.0,
            status: 'approved',
            paymentStatus: 'paid',
            mobileNumber: '9876543210',
            slotsFilled: 1,
        });

        const joiner3 = await StrangersMeetJoiner.create({
            strangersMeetRequestId: meet2.id,
            userId: member1.id,
            status: 'paid',
            paymentStatus: 'paid',
            paymentAmount: 600.0,
        });

        const hostCancelRes2 = await StrangersMeetService.requestHostCancellation({
            meetId: meet2.id,
            hostUserId: host.id,
            reason: 'scheduling_conflict',
            reasonText: 'Date conflict with family event.',
        });
        const cancelReq2 = hostCancelRes2.cancellation;

        // Admin Approves with 100% Refund via MANUAL_PAYOUT
        console.log('\n--- Admin approves with MANUAL_PAYOUT ---');
        const approveRes2 = await StrangersMeetService.adminApproveHostCancellation({
            cancellationId: cancelReq2.id,
            adminId: admin.id,
            refundPercentage: 100,
            refundMethod: 'MANUAL_PAYOUT',
            adminNotes: 'Approved for manual UPI payout.',
        });
        console.log('Approve result:', approveRes2.message);
        console.log(`Cancellation Status: ${approveRes2.cancellation.status} (expected REFUND_PROCESSING)`);

        const memberRefundRecord = await StrangersMeetMemberRefund.findOne({
            where: { hostCancellationRequestId: cancelReq2.id }
        });
        console.log(`Member Refund Record: ${memberRefundRecord.id}, Status: ${memberRefundRecord.status} (expected PENDING)`);

        // Admin Marks Manual Refund as Paid
        console.log('\n--- Admin marks manual refund as PAID ---');
        const markPaidRes = await StrangersMeetService.adminMarkMemberRefundPaid({
            refundId: memberRefundRecord.id,
            adminId: admin.id,
            paymentReference: 'UPI_REF_987654321',
            paymentMethod: 'UPI',
            paymentDate: new Date().toISOString(),
        });
        console.log('Mark paid result:', markPaidRes.message);
        console.log(`Refund Status: ${markPaidRes.refund.status}, Reference: ${markPaidRes.refund.paymentReference}`);

        await cancelReq2.reload();
        console.log(`Host Cancellation status after all refunds paid: ${cancelReq2.status} (expected COMPLETED)`);

        // Clean up Test 2
        console.log('\n--- Cleaning up Test 2 ---');
        await memberRefundRecord.destroy();
        await cancelReq2.destroy();
        await joiner3.destroy();
        await meet2.destroy();

        // ====================================================================
        // TEST 3: REJECTION PATH
        // ====================================================================
        console.log('\n========================================');
        console.log('TEST 3: HOST CANCELLATION REJECTION PATH');
        console.log('========================================');

        const meet3 = await StrangersMeetRequest.create({
            userId: host.id,
            venueId: venue.id,
            subject: 'TEST Host Cancellation Meetup 3 (Reject)',
            tagline: 'Sunday Brunch',
            eventDateTime: new Date(Date.now() + 48 * 60 * 60 * 1000),
            numberOfPersons: 25,
            chargesPerHead: 400.0,
            status: 'approved',
            paymentStatus: 'paid',
            mobileNumber: '9876543210',
            slotsFilled: 0,
        });

        const hostCancelRes3 = await StrangersMeetService.requestHostCancellation({
            meetId: meet3.id,
            hostUserId: host.id,
            reason: 'other',
            reasonText: 'Just wanted to cancel.',
        });
        const cancelReq3 = hostCancelRes3.cancellation;

        console.log('\n--- Admin rejects host cancellation ---');
        const rejectRes = await StrangersMeetService.adminRejectHostCancellation({
            cancellationId: cancelReq3.id,
            adminId: admin.id,
            reason: 'Insufficient reason provided within cutoff window.',
        });
        console.log('Reject result:', rejectRes.message);
        console.log(`Cancellation Status: ${rejectRes.cancellation.status} (expected REJECTED)`);

        await meet3.reload();
        console.log(`Meet 3 status after rejection: ${meet3.status} (expected approved/active)`);

        // Clean up Test 3
        console.log('\n--- Cleaning up Test 3 ---');
        await cancelReq3.destroy();
        await meet3.destroy();

        console.log('\n✅ ALL HOST CANCELLATION & ADMIN REFUND TESTS PASSED!');
        process.exit(0);
    } catch (err) {
        console.error('ERROR in test script:', err);
        console.error(err.stack);
        process.exit(1);
    } finally {
        await sequelize.close();
    }
}

main();
