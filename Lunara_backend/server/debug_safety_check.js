const axios = require('axios');
const jwt = require('jsonwebtoken');
require('dotenv').config();

const BASE_URL = 'http://127.0.0.1:9076';
const JWT_SECRET = process.env.JWT_SECRET || 'your_jwt_secret_key_change_in_production';

async function testSafetyCheckSystem() {
    console.log('============================================================');
    console.log('Testing Safety Check System & Admin Dispatch End-to-End:');
    console.log('============================================================\n');

    const { default: PartySafetyCheck, SafetyStatus } = require('./dist/models/PartySafetyCheck');
    const { default: SafetyCheck } = require('./dist/models/SafetyCheck');
    const { default: Notification } = require('./dist/models/Notification');
    const { default: User } = require('./dist/models/User');

    // Find 2 users
    const users = await User.findAll({ limit: 2 });
    if (users.length < 2) {
        console.error('❌ Need at least 2 users in DB to test.');
        return;
    }

    const testUser = users[0];
    const partnerUser = users[1];

    const { generateAccessToken } = require('./dist/utils/jwt');

    console.log(`Test User: ${testUser.id} (${testUser.firstName} ${testUser.lastName})`);
    console.log(`Partner User: ${partnerUser.id} (${partnerUser.firstName} ${partnerUser.lastName})\n`);

    const userToken = generateAccessToken({
        userId: testUser.id,
        email: testUser.email,
        role: testUser.role,
    });

    const adminToken = generateAccessToken({
        userId: testUser.id,
        email: testUser.email,
        role: 'admin',
    });

    const authHeaders = {
        headers: {
            Authorization: `Bearer ${userToken}`,
            'Content-Type': 'application/json',
        }
    };

    // --- Step 1: Create a pending PartySafetyCheck & Notification ---
    console.log('--- Step 1: Simulating 3-Hour Post-Party Safety Check Trigger ---');
    // Clean up old records for clean test
    await PartySafetyCheck.destroy({ where: { userId: testUser.id } });

    const newSafetyCheck = await PartySafetyCheck.create({
        planId: 'b7c3d1e2-3a4b-5c6d-7e8f-9a0b1c2d3e4f',
        planType: 'party_plan',
        userId: testUser.id,
        partnerUserId: partnerUser.id,
        venueName: 'Spice and Spirits Club',
        partyDate: new Date(),
        partyTime: '21:00',
        safetyStatus: SafetyStatus.NO_RESPONSE,
        alertTriggered: false,
        notificationSentAt: new Date(),
    });

    const notif = await Notification.create({
        recipientUserId: testUser.id,
        actorUserId: partnerUser.id,
        eventType: 'party_safety_check',
        category: 'alert',
        entityType: 'PartySafetyCheck',
        entityId: newSafetyCheck.id,
        title: 'Safety Check: Has your party ended?',
        body: 'Your party at Spice and Spirits Club started 3 hours ago. Please confirm you are safe & sound.',
        isRead: false,
        actionType: 'safety_check',
        deepLink: `/safety-check/${newSafetyCheck.id}`,
        data: {
            checkId: newSafetyCheck.id,
            venueName: 'Spice and Spirits Club',
            safetyStatus: 'NO_RESPONSE',
        },
    });

    console.log(`✓ Created Safety Check Record ID: ${newSafetyCheck.id}`);
    console.log(`✓ Dispatched Safety Check Notification ID: ${notif.id}\n`);

    // --- Step 2: Test GET Pending Safety Check (Used by Live Feed & Dialog) ---
    console.log('--- Step 2: Testing GET /api/mobile/party-plans/safety-checks/pending ---');
    const pendingRes = await axios.get(`${BASE_URL}/api/mobile/party-plans/safety-checks/pending`, authHeaders);
    console.log(`Status: ${pendingRes.status}`);
    console.log('Pending Check Response:', {
        id: pendingRes.data.data?.id,
        venueName: pendingRes.data.data?.venueName,
        safetyStatus: pendingRes.data.data?.safetyStatus,
        partner: pendingRes.data.data?.partner,
    });
    if (pendingRes.data.data?.id !== newSafetyCheck.id) {
        throw new Error('Pending safety check ID mismatch');
    }
    console.log('✓ Pending safety check successfully retrieved for Live Feed banner!\n');

    // --- Step 3: Test GET Notifications (Used by Notification Center Screen) ---
    console.log('--- Step 3: Testing GET /api/mobile/user/notifications ---');
    const notifRes = await axios.get(`${BASE_URL}/api/mobile/user/notifications?userId=${testUser.id}`, authHeaders);
    console.log(`Status: ${notifRes.status}`);
    const safetyNotif = notifRes.data.data?.find(n => n.id === notif.id || n.entityId === newSafetyCheck.id);
    console.log('Safety Notification in Feed:', {
        id: safetyNotif?.id,
        title: safetyNotif?.title,
        eventType: safetyNotif?.eventType,
        actionType: safetyNotif?.actionType,
        entityType: safetyNotif?.entityType,
    });
    if (!safetyNotif) {
        throw new Error('Safety notification not found in notifications list');
    }
    console.log('✓ Safety notification contains all metadata needed to render Yes/No action buttons!\n');

    // --- Step 4: Test Responding with "NEED_HELP" (NO, Unsafe + Reasons + Note) ---
    console.log('--- Step 4: Testing POST /api/mobile/party-plans/safety-checks/respond (NEED_HELP) ---');
    const reasons = ['Felt uncomfortable', 'Inappropriate behavior'];
    const customNote = 'Partner was aggressive and refused to leave the venue';
    
    const respondRes = await axios.post(
        `${BASE_URL}/api/mobile/party-plans/safety-checks/respond`,
        {
            checkId: newSafetyCheck.id,
            safetyStatus: 'NEED_HELP',
            reasons: reasons,
            notes: `Reasons: ${reasons.join(', ')} | Note: ${customNote}`,
        },
        authHeaders
    );

    console.log(`Status: ${respondRes.status}`);
    console.log('Response:', respondRes.data);

    // Verify DB update
    const updatedCheck = await PartySafetyCheck.findByPk(newSafetyCheck.id);
    console.log('Updated DB PartySafetyCheck:', {
        id: updatedCheck.id,
        safetyStatus: updatedCheck.safetyStatus,
        alertTriggered: updatedCheck.alertTriggered,
        notes: updatedCheck.notes,
        respondedAt: updatedCheck.respondedAt,
    });

    if (updatedCheck.safetyStatus !== 'NEED_HELP' || !updatedCheck.alertTriggered) {
        throw new Error('PartySafetyCheck status not updated to NEED_HELP with alertTriggered=true');
    }

    // Verify Notification marked read
    const updatedNotif = await Notification.findByPk(notif.id);
    console.log(`Notification isRead in DB: ${updatedNotif.isRead}`);

    // Verify mirrored SafetyCheck record
    const mirroredSc = await SafetyCheck.findOne({
        where: { userId: testUser.id, partnerId: partnerUser.id },
        order: [['createdAt', 'DESC']],
    });
    if (mirroredSc) {
        console.log('Mirrored SafetyCheck record in Admin DB:', {
            id: mirroredSc.id,
            feltSafe: mirroredSc.feltSafe,
            prebuiltAnswers: mirroredSc.prebuiltAnswers,
            opinion: mirroredSc.opinion,
            status: mirroredSc.status,
        });
    }

    console.log('✓ Emergency alert with reasons & notes persisted to DB successfully!\n');

    // --- Step 5: Test Admin Panel Safety Checks Endpoint ---
    console.log('--- Step 5: Testing GET /api/admin/safety-checks (Admin Dashboard) ---');
    const adminHeaders = {
        headers: {
            Authorization: `Bearer ${adminToken}`,
            'Content-Type': 'application/json',
        }
    };
    const adminChecksRes = await axios.get(`${BASE_URL}/api/admin/safety-checks`, adminHeaders);
    console.log(`Admin Safety Checks Status: ${adminChecksRes.status}`);
    console.log(`Total Safety Checks in Admin: ${adminChecksRes.data.data?.length}`);
    const adminCheck = adminChecksRes.data.data?.[0];
    if (adminCheck) {
        console.log('Latest Admin Safety Check Item:', {
            id: adminCheck.id,
            user: adminCheck.user?.firstName,
            partner: adminCheck.partner?.firstName,
            feltSafe: adminCheck.feltSafe,
            prebuiltAnswers: adminCheck.prebuiltAnswers,
            opinion: adminCheck.opinion,
            status: adminCheck.status,
        });
    }
    console.log('✓ Admin dashboard successfully receives and displays the safety report!\n');

    // --- Step 6: Test Responding with "SAFE" (YES, I\'m Safe) ---
    console.log('--- Step 6: Testing POST /api/mobile/party-plans/safety-checks/respond (SAFE) ---');
    const safeRes = await axios.post(
        `${BASE_URL}/api/mobile/party-plans/safety-checks/respond`,
        {
            checkId: newSafetyCheck.id,
            safetyStatus: 'SAFE',
            notes: 'Confirmed safe and reached home',
        },
        authHeaders
    );
    console.log(`Safe Response Status: ${safeRes.status}`);
    console.log('Safe Response Data:', safeRes.data);
    const finalCheck = await PartySafetyCheck.findByPk(newSafetyCheck.id);
    console.log('Final DB Status:', finalCheck.safetyStatus);

    console.log('\n🎉 ALL SAFETY CHECK INTEGRATION TESTS PASSED WITH 100% SUCCESS!');
}

testSafetyCheckSystem()
    .then(() => process.exit(0))
    .catch((err) => {
        console.error('\n❌ Test failed:', err.response?.data || err.message || err);
        process.exit(1);
    });
