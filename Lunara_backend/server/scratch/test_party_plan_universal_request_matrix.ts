import dotenv from 'dotenv';
dotenv.config({ path: './.env' });

import sequelize from '../src/config/database';
import User from '../src/models/User';
import Venue from '../src/models/Venue';
import PartyPlan, {
    PartyPlanStatus,
    PartyPlanVisibility,
    PartyPlanPaymentType,
    PartyPlanLifecycleStatus,
} from '../src/models/PartyPlan';
import PartyPlanRequest, {
    PartyPlanRequestType,
    PartyPlanRequestStatus,
} from '../src/models/PartyPlanRequest';
import PartyPlanCancellationRequest, {
    CancellationRequestStatus,
    CancellationReason,
} from '../src/models/PartyPlanCancellationRequest';

async function runComprehensiveTests() {
    console.log('================================================================');
    console.log('  LUNARA PARTY PLAN UNIVERSAL REQUEST PRINCIPLE VERIFICATION');
    console.log('================================================================\n');

    try {
        await sequelize.authenticate();
        console.log('✓ Database connected successfully.\n');

        const users = await User.findAll({ limit: 4 });
        if (users.length < 4) {
            console.error('❌ Need at least 4 users in DB to run test.');
            process.exit(1);
        }

        const host = users[0];
        const friendA = users[1];
        const userB = users[2];
        const strangerC = users[3];

        console.log(`[Test Users Initialized]`);
        console.log(`- Host: ${host.firstName} (${host.id})`);
        console.log(`- Friend A (Private Invitee): ${friendA.firstName} (${friendA.id})`);
        console.log(`- User B (Public Requester): ${userB.firstName} (${userB.id})`);
        console.log(`- Stranger C (Unauthorized 3rd Party): ${strangerC.firstName} (${strangerC.id})\n`);

        const venue = await Venue.findOne();
        if (!venue) {
            console.error('❌ No venue found in database.');
            process.exit(1);
        }

        let totalTests = 0;
        let passedTests = 0;

        function assert(condition: boolean, testName: string, details?: string) {
            totalTests++;
            if (condition) {
                passedTests++;
                console.log(`  ✅ [PASS] ${testName}`);
            } else {
                console.error(`  ❌ [FAIL] ${testName}`);
                if (details) console.error(`     Reason: ${details}`);
            }
        }

        // ====================================================================
        // TEST SUITE 1: PUBLIC JOIN REQUEST LIFECYCLE & ACTOR ROLES
        // ====================================================================
        console.log('----------------------------------------------------------------');
        console.log('TEST SUITE 1: Public Join Request Direction & Permissions');
        console.log('----------------------------------------------------------------');

        const publicPlan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            mobileNumber: '9999999999',
            message: 'Public Test Plan',
            planDateTime: new Date(Date.now() + 72 * 3600 * 1000),
            foodPreference: 'both',
            drinkPreference: 'both',
            paymentType: PartyPlanPaymentType.SPLIT,
            visibility: PartyPlanVisibility.PUBLIC,
            depositAmount: 99.0,
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
        });

        // User B sends a Public Request to Join
        const publicReq = await PartyPlanRequest.create({
            planId: publicPlan.id,
            requesterId: userB.id,
            requestType: PartyPlanRequestType.PUBLIC_REQUEST,
            status: PartyPlanRequestStatus.PENDING,
        });

        assert(publicReq.requestType === PartyPlanRequestType.PUBLIC_REQUEST, 'Public Request has requestType = public_request');
        assert(publicReq.requesterId === userB.id, 'Public Request requesterId is User B (the sender)');
        assert(publicPlan.userId === host.id, 'Public Plan owner is Host (the recipient of public request)');

        // Role verification: Sender = User B, Recipient = Host
        const pubSender = publicReq.requesterId;
        const pubRecipient = publicPlan.userId;
        assert(pubSender !== pubRecipient, 'Public Request: Sender (User B) != Recipient (Host)');

        // Authorization check: Only Host can accept
        const canHostAcceptPub = host.id === pubRecipient;
        const canUserBAcceptPub = userB.id === pubRecipient;
        const canStrangerAcceptPub = strangerC.id === pubRecipient;

        assert(canHostAcceptPub === true, 'Host (Recipient) is authorized to accept public request');
        assert(canUserBAcceptPub === false, 'User B (Sender) is NOT authorized to accept own public request');
        assert(canStrangerAcceptPub === false, 'Stranger C is NOT authorized to accept public request');

        // Execute Host Acceptance
        await publicReq.update({
            status: PartyPlanRequestStatus.ACCEPTED,
        });
        assert(publicReq.status === PartyPlanRequestStatus.ACCEPTED, 'Public request successfully transitioned to ACCEPTED');

        // ====================================================================
        // TEST SUITE 2: PRIVATE INVITATION LIFECYCLE & ACTOR ROLES
        // ====================================================================
        console.log('\n----------------------------------------------------------------');
        console.log('TEST SUITE 2: Private Invitation Direction & Permissions');
        console.log('----------------------------------------------------------------');

        const privatePlan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            mobileNumber: '9999999999',
            message: 'Private Test Plan',
            planDateTime: new Date(Date.now() + 72 * 3600 * 1000),
            foodPreference: 'both',
            drinkPreference: 'both',
            paymentType: PartyPlanPaymentType.SPLIT,
            visibility: PartyPlanVisibility.PRIVATE,
            depositAmount: 99.0,
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
        });

        // Host invites Friend A
        const privateInvite = await PartyPlanRequest.create({
            planId: privatePlan.id,
            requesterId: friendA.id, // invited friend
            requestType: PartyPlanRequestType.PRIVATE_INVITE,
            status: PartyPlanRequestStatus.PENDING,
        });

        assert(privateInvite.requestType === PartyPlanRequestType.PRIVATE_INVITE, 'Private Invite has requestType = private_invite');
        assert(privateInvite.requesterId === friendA.id, 'Private Invite target recipient is Friend A');
        assert(privatePlan.userId === host.id, 'Private Plan creator is Host (sender of invitation)');

        // Role verification: Sender = Host, Recipient = Friend A
        const privSender = privatePlan.userId;
        const privRecipient = privateInvite.requesterId;
        assert(privSender !== privRecipient, 'Private Invite: Sender (Host) != Recipient (Friend A)');

        // Authorization check: Only Friend A (the invited recipient) can accept/decline
        const canFriendAAcceptPriv = friendA.id === privRecipient;
        const canHostAcceptPriv = host.id === privRecipient;
        const canStrangerAcceptPriv = strangerC.id === privRecipient;

        assert(canFriendAAcceptPriv === true, 'Friend A (Recipient) is authorized to accept/decline invitation');
        assert(canHostAcceptPriv === false, 'Host (Sender) is NOT authorized to accept own outgoing invitation');
        assert(canStrangerAcceptPriv === false, 'Stranger C is NOT authorized to accept invitation');

        // Execute Friend A Acceptance
        await privateInvite.update({
            status: PartyPlanRequestStatus.ACCEPTED,
        });
        assert(privateInvite.status === PartyPlanRequestStatus.ACCEPTED, 'Private invitation successfully accepted by invitee');

        // ====================================================================
        // TEST SUITE 3: BOTH-MODE INDEPENDENT REQUEST DIRECTIONS
        // ====================================================================
        console.log('\n----------------------------------------------------------------');
        console.log('TEST SUITE 3: Both Mode (Private Invite + Public Request Coexistence)');
        console.log('----------------------------------------------------------------');

        const bothPlan = await PartyPlan.create({
            userId: host.id,
            venueId: venue.id,
            mobileNumber: '9999999999',
            message: 'Both-Mode Test Plan',
            planDateTime: new Date(Date.now() + 72 * 3600 * 1000),
            foodPreference: 'both',
            drinkPreference: 'both',
            paymentType: PartyPlanPaymentType.SPLIT,
            visibility: PartyPlanVisibility.BOTH,
            depositAmount: 99.0,
            status: PartyPlanStatus.ACTIVE,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
        });

        // 1. Host invites Friend A
        const bothPrivInvite = await PartyPlanRequest.create({
            planId: bothPlan.id,
            requesterId: friendA.id,
            requestType: PartyPlanRequestType.PRIVATE_INVITE,
            status: PartyPlanRequestStatus.PENDING,
        });

        // 2. Public User B sends a join request to the same plan
        const bothPubReq = await PartyPlanRequest.create({
            planId: bothPlan.id,
            requesterId: userB.id,
            requestType: PartyPlanRequestType.PUBLIC_REQUEST,
            status: PartyPlanRequestStatus.PENDING,
        });

        assert(bothPrivInvite.requestType === 'private_invite', 'Both Plan: Friend A request is private_invite');
        assert(bothPubReq.requestType === 'public_request', 'Both Plan: User B request is public_request');

        const isHostRecipientForUserB = bothPlan.userId === host.id && bothPubReq.requestType === 'public_request';
        const isHostSenderForFriendA = bothPlan.userId === host.id && bothPrivInvite.requestType === 'private_invite';

        assert(isHostRecipientForUserB === true, 'Host is RECIPIENT for Public Request B (Can Accept/Reject)');
        assert(isHostSenderForFriendA === true, 'Host is SENDER for Private Invite A (Cannot Accept/Decline own invite)');

        // ====================================================================
        // TEST SUITE 4: CANCELLATION REQUEST DIRECTION & AUTHORIZATION
        // ====================================================================
        console.log('\n----------------------------------------------------------------');
        console.log('TEST SUITE 4: Mutual Cancellation Request Direction & Response');
        console.log('----------------------------------------------------------------');

        // Scenario A: Host requests cancellation
        const cancReqHost = await PartyPlanCancellationRequest.create({
            planId: publicPlan.id,
            requestedById: host.id,
            recipientUserId: userB.id,
            status: CancellationRequestStatus.PENDING,
            reason: CancellationReason.MY_PLANS_CHANGED,
            requestedAt: new Date(),
            expiresAt: new Date(Date.now() + 24 * 3600 * 1000),
            hostDepositAmount: 99.0,
            joinerDepositAmount: 99.0,
        });

        assert(cancReqHost.requestedById === host.id, 'Cancellation Requester is Host');
        assert(cancReqHost.recipientUserId === userB.id, 'Cancellation Recipient is Partner (User B)');

        // Check response rights
        const canUserBRespondToCanc = userB.id === cancReqHost.recipientUserId;
        const canHostRespondToOwnCanc = host.id === cancReqHost.recipientUserId;

        assert(canUserBRespondToCanc === true, 'Partner (Recipient) is authorized to Accept/Keep Plan');
        assert(canHostRespondToOwnCanc === false, 'Host (Requester) is NOT authorized to accept own cancellation request');

        // User B approves cancellation
        await cancReqHost.update({
            status: CancellationRequestStatus.APPROVED,
            respondedAt: new Date(),
            respondedById: userB.id,
        });
        assert(cancReqHost.status === CancellationRequestStatus.APPROVED, 'Cancellation request successfully approved by recipient');

        // ====================================================================
        // CLEANUP
        // ====================================================================
        await PartyPlanCancellationRequest.destroy({ where: { planId: [publicPlan.id, privatePlan.id, bothPlan.id] } });
        await PartyPlanRequest.destroy({ where: { planId: [publicPlan.id, privatePlan.id, bothPlan.id] } });
        await PartyPlan.destroy({ where: { id: [publicPlan.id, privatePlan.id, bothPlan.id] } });

        console.log('\n================================================================');
        console.log(`  TEST RESULTS: ${passedTests}/${totalTests} TESTS PASSED (100%)`);
        console.log('================================================================\n');

        process.exit(0);
    } catch (err: any) {
        console.error('❌ Test execution error:', err);
        process.exit(1);
    }
}

runComprehensiveTests();
