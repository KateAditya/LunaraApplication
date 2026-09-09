/**
 * Party Plan — Targeted Integration Test Suite
 *
 * Scope (strictly):
 *   BUG-1: Unpaid party plans (hostPaymentStatus=unpaid, isLive=false) MUST NOT
 *           appear in the public feed (GET /api/mobile/party-plans) or
 *           the live feed (GET /api/mobile/plans/live-feed).
 *
 *   BUG-2: Join request status (pending → accepted → payment_pending → matched)
 *           MUST be reflected on both requester and host side within 2 seconds via
 *           socket event + local cache invalidation.
 *
 * Regression safety:
 *   - Upcoming Night posts (isUpcomingNight=true) bypass payment gate → stays UNTOUCHED
 *   - Host's own unpaid plans are visible to the host only (via requesterId param) → UNTOUCHED
 *   - Private invite flow stays UNTOUCHED
 *   - Group party / Table Plan creation stays UNTOUCHED
 *   - All payment math (₹99 deposit, Razorpay orders) stays UNTOUCHED
 *   - All lifecycle transitions (POSTED→REQUEST_RECEIVED→PAYMENT_PENDING→MATCH_CONFIRMED) → UNTOUCHED
 *   - Time-lock (4-hour gap) validation → UNTOUCHED
 *   - confirmMatch / autoOpenChat / ticket generation → UNTOUCHED
 *
 * Test runner: Jest  (ts-jest)
 * Run:  npx jest --testPathPattern partyPlan.test.ts --forceExit
 */

import request from 'supertest';
import app from '../server';
import sequelize from '../config/database';
import PartyPlan, {
    PartyPlanStatus,
    PartyPlanVisibility,
    PartyPlanPaymentStatus,
    PartyPlanLifecycleStatus,
    PartyPlanPaymentType,
} from '../models/PartyPlan';
import PartyPlanRequest, {
    PartyPlanRequestStatus,
} from '../models/PartyPlanRequest';
import User from '../models/User';
import Venue from '../models/Venue';
import { generateAccessToken } from '../utils/jwt';

jest.mock('razorpay', () => {
    return jest.fn().mockImplementation(() => {
        return {
            orders: {
                create: jest.fn().mockImplementation((options: any) => {
                    return Promise.resolve({
                        id: `order_mock_${Math.random().toString(36).substr(2, 9)}`,
                        amount: options.amount,
                        currency: options.currency,
                    });
                }),
            },
        };
    });
});

jest.mock('../services/fcmService', () => ({
    sendPushNotification: jest.fn().mockResolvedValue(true),
    sendMulticastPushNotification: jest.fn().mockResolvedValue(true),
}));

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Create a minimal test user and return its id + auth token. */
async function createTestUser(suffix: string): Promise<{ id: string; token: string }> {
    const phone = `+91999900${suffix.slice(0, 4)}`;
    let user = await User.findOne({ where: { phone } });
    if (!user) {
        user = await User.create({
            firstName: `Test${suffix}`,
            lastName: 'User',
            phone,
            email: `test_${suffix}@lunara-test.invalid`,
            isVerified: true,
            city: 'Pune',
            dateOfBirth: '1995-01-01',
            passwordHash: 'dummyhash',
        } as any);
    }
    const token = generateAccessToken({ userId: user.id, email: user.email, role: user.role || 'user' });
    return { id: user.id, token };
}

/** Create (or reuse) a minimal test venue. */
async function getTestVenue(): Promise<string> {
    let venue = await Venue.findOne({ where: { name: 'Lunara Test Venue' } });
    if (!venue) {
        venue = await Venue.create({
            name: 'Lunara Test Venue',
            addressLine1: '1 Test Street',
            city: 'Pune',
            area: 'Koregaon Park',
            category: 'Nightclub',
            isActive: true,
        } as any);
    }
    return venue.id;
}

/** ISO datetime 3 days in the future (safe for time-lock checks). */
function futurePlanDateTime(daysFromNow = 3): string {
    const dt = new Date();
    dt.setDate(dt.getDate() + daysFromNow);
    dt.setHours(21, 0, 0, 0);
    return dt.toISOString();
}

/** Create an UNPAID party plan directly in the DB (simulates state right after createPartyPlan API call). */
async function createUnpaidPlan(hostId: string, venueId: string, opts: { visibility?: PartyPlanVisibility; selectedUsers?: string[] } = {}): Promise<PartyPlan> {
    return PartyPlan.create({
        userId: hostId,
        venueId,
        message: 'Test party plan - unpaid',
        planDateTime: futurePlanDateTime(3),
        status: PartyPlanStatus.ACTIVE,
        visibility: opts.visibility ?? PartyPlanVisibility.PUBLIC,
        selectedUsers: opts.selectedUsers ?? null,
        depositAmount: 99,
        hostPaymentStatus: PartyPlanPaymentStatus.UNPAID,
        hostRazorpayOrderId: `order_mock_${Date.now()}`,
        isLive: false,   // ← UNPAID = not live
        lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
        paymentStatus: 'pending',
        foodPreference: 'Both',
        drinkPreference: 'Both',
        paymentType: PartyPlanPaymentType.SPLIT,
        showProfilePhoto: true,
        showHostName: true,
        showVenueDetails: true,
        showDateDetails: true,
        expiresAt: futurePlanDateTime(3),
    } as any);
}

/** Create a PAID (live) party plan directly in the DB. */
async function createPaidPlan(hostId: string, venueId: string, opts: { visibility?: PartyPlanVisibility; selectedUsers?: string[] } = {}): Promise<PartyPlan> {
    return PartyPlan.create({
        userId: hostId,
        venueId,
        message: 'Test party plan - paid',
        planDateTime: futurePlanDateTime(4),
        status: PartyPlanStatus.ACTIVE,
        visibility: opts.visibility ?? PartyPlanVisibility.PUBLIC,
        selectedUsers: opts.selectedUsers ?? null,
        depositAmount: 99,
        hostPaymentStatus: PartyPlanPaymentStatus.PAID,
        hostRazorpayOrderId: `order_mock_${Date.now()}`,
        isLive: true,    // ← PAID = live
        lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
        paymentStatus: 'paid',
        foodPreference: 'Both',
        drinkPreference: 'Both',
        paymentType: PartyPlanPaymentType.SPLIT,
        showProfilePhoto: true,
        showHostName: true,
        showVenueDetails: true,
        showDateDetails: true,
        expiresAt: futurePlanDateTime(4),
    } as any);
}

// ─── Setup / Teardown ─────────────────────────────────────────────────────────

let hostA: { id: string; token: string };
let hostB: { id: string; token: string };
let joiner: { id: string; token: string };
let venueId: string;

beforeAll(async () => {
    await sequelize.authenticate();
    [hostA, hostB, joiner, venueId] = await Promise.all([
        createTestUser('HOSTA1'),
        createTestUser('HOSTB2'),
        createTestUser('JOINR3'),
        getTestVenue(),
    ]);
}, 30_000);

afterAll(async () => {
    await sequelize.close();
}, 10_000);

// Clean up any plans created during tests so they don't interfere with each other
afterEach(async () => {
    await PartyPlanRequest.destroy({ where: { requesterId: joiner.id }, force: true });
    await PartyPlan.destroy({ where: { userId: hostA.id }, force: true });
    await PartyPlan.destroy({ where: { userId: hostB.id }, force: true });
}, 15_000);

// ═════════════════════════════════════════════════════════════════════════════
// SECTION 1: BUG-1 — Public feed must NOT show unpaid party plans
// ═════════════════════════════════════════════════════════════════════════════

describe('BUG-1: Party Plan Feed Visibility — Unpaid plans hidden from public', () => {

    // ─── 1.1  GET /api/mobile/party-plans — discovery feed ───────────────────

    test('1.1a — Unpaid plan (isLive=false) does NOT appear in the public discovery feed', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active' })
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).not.toContain(unpaid.id);
    });

    test('1.1b — Paid (isLive=true) plan DOES appear in the public discovery feed', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active' })
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).toContain(paid.id);
    });

    test('1.1c — Unpaid plan does NOT appear in the discovery feed even when requesterId belongs to someone else (not the host)', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active', requesterId: joiner.id })
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).not.toContain(unpaid.id);
    });

    test('1.1d — Host CAN see their own unpaid plan when requesterId equals their own userId', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active', requesterId: hostA.id })
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).toContain(unpaid.id);
    });

    // ─── 1.2  GET /api/mobile/plans/live-feed — live feed ────────────────────

    test('1.2a — Unpaid plan (isLive=false) does NOT appear in the live feed even when viewer is authenticated', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get('/api/mobile/plans/live-feed')
            .set('Authorization', `Bearer ${joiner.token}`)
            .expect(200);

        const partyPlanIds: string[] = (res.body.data ?? [])
            .filter((item: any) => item.type === 'party_plan' || item.planType === 'party_plan' || item.id === unpaid.id)
            .map((item: any) => item.id ?? item.planId);

        expect(partyPlanIds).not.toContain(unpaid.id);
    });

    test('1.2b — Paid plan DOES appear in the live feed for an authenticated viewer', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get('/api/mobile/plans/live-feed')
            .set('Authorization', `Bearer ${joiner.token}`)
            .expect(200);

        const partyPlanIds: string[] = (res.body.data ?? []).map((item: any) => item.id ?? item.planId);
        expect(partyPlanIds).toContain(paid.id);
    });

    test('1.2c — Host\'s OWN unpaid plan appears in myHostPartyPlans (pendingPayments) section of live feed, not in the public data array', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get('/api/mobile/plans/live-feed')
            .set('Authorization', `Bearer ${hostA.token}`)
            .expect(200);

        const publicIds: string[] = (res.body.data ?? []).map((item: any) => item.id ?? item.planId);
        const pendingPaymentIds: string[] = (res.body.pendingPayments ?? []).map((p: any) => p.id ?? p.planId);

        // Should NOT appear in the shared public data
        expect(publicIds).not.toContain(unpaid.id);
        // MAY appear in host's personal pendingPayments section
        expect(pendingPaymentIds).toContain(unpaid.id);
    });

    // ─── 1.3  Upcoming Night bypass — must stay unaffected ───────────────────

    test('1.3a — Upcoming Night post (isLive=true, hostPaymentStatus=paid immediately on creation) appears in the public feed', async () => {
        // Upcoming nights are PAID + LIVE from the moment of creation (see line 1040-1041 in partyPlanController.ts)
        const upcomingNight = await PartyPlan.create({
            userId: hostB.id,
            venueId,
            message: 'Upcoming Night Test',
            planDateTime: futurePlanDateTime(5),
            status: PartyPlanStatus.ACTIVE,
            visibility: PartyPlanVisibility.PUBLIC,
            depositAmount: 0,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
            paymentStatus: 'paid',
            foodPreference: 'Both',
            drinkPreference: 'Both',
            paymentType: PartyPlanPaymentType.SPLIT,
            showProfilePhoto: true,
            showHostName: true,
            showVenueDetails: true,
            showDateDetails: true,
            expiresAt: futurePlanDateTime(5),
        } as any);

        const res = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active' })
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).toContain(upcomingNight.id);

        await upcomingNight.destroy({ force: true });
    });

    // ─── 1.4  Private plan visibility ─────────────────────────────────────────

    test('1.4a — A PAID private plan does NOT appear in the public feed (no requesterId)', async () => {
        const privatePlan = await createPaidPlan(hostA.id, venueId, {
            visibility: PartyPlanVisibility.PRIVATE,
            selectedUsers: [joiner.id],
        });

        const res = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active' })
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).not.toContain(privatePlan.id);
    });

    test('1.4b — A PAID private plan DOES appear when requesterId matches an invited user', async () => {
        const privatePlan = await createPaidPlan(hostA.id, venueId, {
            visibility: PartyPlanVisibility.PRIVATE,
            selectedUsers: [joiner.id],
        });

        const res = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active', requesterId: joiner.id })
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).toContain(privatePlan.id);
    });

    test('1.4c — An UNPAID private plan does NOT appear even for the invited user', async () => {
        const privatePlanUnpaid = await createUnpaidPlan(hostA.id, venueId, {
            visibility: PartyPlanVisibility.PRIVATE,
            selectedUsers: [joiner.id],
        });

        const res = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active', requesterId: joiner.id })
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).not.toContain(privatePlanUnpaid.id);
    });
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION 2: BUG-2 — Join request status must update within 2 seconds
//   We test API response time and socket event emission separately
// ═════════════════════════════════════════════════════════════════════════════

describe('BUG-2: Join request status update speed and accuracy', () => {

    // ─── 2.1  API response time for POST /requests ────────────────────────────

    test('2.1 — POST /api/mobile/party-plans/:id/requests responds within 2000ms', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        const start = Date.now();
        const res = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);
        const elapsed = Date.now() - start;

        expect(res.body.success).toBe(true);
        expect(elapsed).toBeLessThan(2000);
    });

    // ─── 2.2  Request data returned immediately in the POST 201 response ──────

    test('2.2 — POST /requests returns the new request object with status=pending immediately', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        const res = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);

        expect(res.body.data).toBeDefined();
        expect(res.body.data.status).toBe('pending');
        expect(res.body.data.planId).toBe(paid.id);
        expect(res.body.data.requesterId).toBe(joiner.id);
    });

    // ─── 2.3  GET /requests/user/:userId returns the new request without delay ─

    test('2.3 — GET /requests/user/:userId returns the pending request immediately after creation', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);

        const res = await request(app)
            .get(`/api/mobile/party-plans/requests/user/${joiner.id}`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .expect(200);

        const matchingReq = (res.body.data ?? []).find((r: any) => r.planId === paid.id);
        expect(matchingReq).toBeDefined();
        expect(matchingReq.status).toBe('pending');
    });

    // ─── 2.4  GET /api/mobile/party-plans/:id/requests — host view ───────────

    test('2.4 — GET /party-plans/:id/requests responds with the pending request within 2000ms (host view)', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        // Joiner sends request
        await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);

        const start = Date.now();
        const res = await request(app)
            .get(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .expect(200);
        const elapsed = Date.now() - start;

        const reqs = res.body.data ?? [];
        expect(reqs.length).toBeGreaterThanOrEqual(1);
        expect(reqs.some((r: any) => r.requesterId === joiner.id && r.status === 'pending')).toBe(true);
        expect(elapsed).toBeLessThan(2000);
    });

    // ─── 2.5  Accept request — status transitions to payment_pending < 2s ─────

    test('2.5 — POST /requests/:reqId/accept updates status to payment_pending or accepted within 2000ms', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        const reqRes = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);

        const reqId: string = reqRes.body.data.id;

        const start = Date.now();
        const acceptRes = await request(app)
            .post(`/api/mobile/party-plans/requests/${reqId}/accept`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .send({ userId: hostA.id })
            .expect(200);
        const elapsed = Date.now() - start;

        expect(acceptRes.body.success).toBe(true);
        expect(elapsed).toBeLessThan(2000);

        // Verify DB state
        const updatedReq = await PartyPlanRequest.findByPk(reqId);
        expect([
            PartyPlanRequestStatus.ACCEPTED,
            PartyPlanRequestStatus.PAYMENT_PENDING,
        ]).toContain(updatedReq?.status);
    });

    // ─── 2.6  Joiner queries their request after host acceptance < 2s ─────────

    test('2.6 — Joiner can retrieve accepted/payment_pending status via GET /requests/user immediately after host accepts', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        const reqRes = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);

        const reqId: string = reqRes.body.data.id;

        await request(app)
            .post(`/api/mobile/party-plans/requests/${reqId}/accept`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .send({ userId: hostA.id })
            .expect(200);

        // Immediately query joiner's requests — no polling/wait
        const start = Date.now();
        const joinerReqRes = await request(app)
            .get(`/api/mobile/party-plans/requests/user/${joiner.id}`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .expect(200);
        const elapsed = Date.now() - start;

        const updatedReq = (joinerReqRes.body.data ?? []).find((r: any) => r.id === reqId);
        expect(updatedReq).toBeDefined();
        expect([
            'accepted',
            'payment_pending',
        ]).toContain(updatedReq.status);
        expect(elapsed).toBeLessThan(2000);
    });

    // ─── 2.7  Idempotency: duplicate join request is rejected properly ─────────

    test('2.7 — Sending a duplicate join request returns 409 with a clear message (not 500)', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);

        const res = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(409);

        expect(res.body.success).toBe(false);
        expect(typeof res.body.message).toBe('string');
        expect(res.body.message.length).toBeGreaterThan(0);
    });

    // ─── 2.8  Joining an UNPAID plan is rejected (plan not live) ─────────────

    test('2.8 — Attempting to join an UNPAID party plan (isLive=false) returns 400 with PARTY_PLAN_NOT_ACTIVE', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        const res = await request(app)
            .post(`/api/mobile/party-plans/${unpaid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(400);

        expect(res.body.success).toBe(false);
        expect(res.body.code).toBe('PARTY_PLAN_NOT_ACTIVE');
    });

    // ─── 2.9  Host cannot join their own plan ─────────────────────────────────

    test('2.9 — Host cannot send a join request to their own plan (400)', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        const res = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .send({ userId: hostA.id })
            .expect(400);

        expect(res.body.success).toBe(false);
    });

    // ─── 2.10  Cancel request — status reflects immediately in joiner's list ───

    test('2.10 — After joiner cancels their pending request, GET /requests/user shows status=cancelled immediately', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        const reqRes = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);

        const reqId: string = reqRes.body.data.id;

        await request(app)
            .post(`/api/mobile/party-plans/requests/${reqId}/cancel`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(200);

        const joinerReqRes = await request(app)
            .get(`/api/mobile/party-plans/requests/user/${joiner.id}`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .expect(200);

        const cancelledReq = (joinerReqRes.body.data ?? []).find((r: any) => r.id === reqId);
        // After cancellation, the request may be omitted from the default listing or shown as cancelled
        // Either is acceptable — it must NOT still show as 'pending'
        if (cancelledReq) {
            expect(cancelledReq.status).not.toBe('pending');
        }
    });
});

// ═════════════════════════════════════════════════════════════════════════════
// SECTION 3: Regression tests — existing business logic must remain intact
// ═════════════════════════════════════════════════════════════════════════════

describe('REGRESSION: Existing business logic must be unaffected', () => {

    // ─── 3.1  createPartyPlan API — basic creation still works ────────────────

    test('3.1 — POST /api/mobile/party-plans creates a plan with isLive=false and hostPaymentStatus=unpaid by default', async () => {
        const planDateTime = futurePlanDateTime(6);

        const res = await request(app)
            .post('/api/mobile/party-plans')
            .set('Authorization', `Bearer ${hostA.token}`)
            .send({
                userId: hostA.id,
                venueId,
                message: 'Regression test plan creation',
                planDateTime,
                visibility: 'public',
            })
            .expect(201);

        expect(res.body.success).toBe(true);
        expect(res.body.data.isLive).toBe(false);
        expect(res.body.data.hostPaymentStatus).toBe(PartyPlanPaymentStatus.UNPAID);

        // Also verify Razorpay order info is included so frontend can initiate payment
        expect(res.body.razorpayOrderId).toBeDefined();
        expect(res.body.amount).toBe(9900); // ₹99 in paise
    });

    // ─── 3.2  getPlansByUser — host sees their own plans ─────────────────────

    test('3.2 — GET /party-plans/user/:userId returns both paid and unpaid plans for the plan owner', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);
        const paid = await createPaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get(`/api/mobile/party-plans/user/${hostA.id}`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .expect(200);

        const ids: string[] = (res.body.data ?? []).map((p: any) => p.id);
        expect(ids).toContain(unpaid.id);
        expect(ids).toContain(paid.id);
    });

    // ─── 3.3  getPartyPlanById — returns plan for host regardless of payment ──

    test('3.3 — GET /party-plans/:id returns the plan for its owner even when unpaid', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        const res = await request(app)
            .get(`/api/mobile/party-plans/${unpaid.id}`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .expect(200);

        expect(res.body.data?.id ?? res.body.id).toBe(unpaid.id);
    });

    // ─── 3.4  verifyHostPayment — post-payment, plan becomes isLive=true ──────

    test('3.4 — POST /party-plans/:id/host-pay with mock payment sets hostPaymentStatus=paid and isLive=true', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        const res = await request(app)
            .post(`/api/mobile/party-plans/${unpaid.id}/host-pay`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .send({
                userId: hostA.id,
                razorpay_order_id: unpaid.hostRazorpayOrderId,
                razorpay_payment_id: `pay_mock_${Date.now()}`,
                razorpay_signature: 'mock_signature',
            })
            .expect(200);

        expect(res.body.success).toBe(true);

        const reloaded = await PartyPlan.findByPk(unpaid.id);
        expect(reloaded?.hostPaymentStatus).toBe(PartyPlanPaymentStatus.PAID);
        expect(reloaded?.isLive).toBe(true);
    });

    // ─── 3.5  After host payment, the plan appears in the public feed ─────────

    test('3.5 — After verifyHostPayment succeeds, the plan appears in the public discovery feed', async () => {
        const unpaid = await createUnpaidPlan(hostA.id, venueId);

        await request(app)
            .post(`/api/mobile/party-plans/${unpaid.id}/host-pay`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .send({
                userId: hostA.id,
                razorpay_order_id: unpaid.hostRazorpayOrderId,
                razorpay_payment_id: `pay_mock_${Date.now()}`,
                razorpay_signature: 'mock_signature',
            })
            .expect(200);

        const feedRes = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active' })
            .expect(200);

        const ids: string[] = (feedRes.body.data ?? []).map((p: any) => p.id);
        expect(ids).toContain(unpaid.id);
    });

    // ─── 3.6  Plan cancelled via PATCH /:id/status is hidden from feed ────────

    test('3.6 — A cancelled plan does NOT appear in the active discovery feed', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        await request(app)
            .patch(`/api/mobile/party-plans/${paid.id}/status`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .send({ userId: hostA.id, status: 'cancelled' })
            .expect(200);

        const feedRes = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active' })
            .expect(200);

        const ids: string[] = (feedRes.body.data ?? []).map((p: any) => p.id);
        expect(ids).not.toContain(paid.id);
    });

    // ─── 3.7  Expired plan filter ─────────────────────────────────────────────

    test('3.7 — A plan whose planDateTime is in the past does NOT appear in the active discovery feed', async () => {
        // Create an expired plan directly in DB
        const expired = await PartyPlan.create({
            userId: hostA.id,
            venueId,
            message: 'Expired plan',
            planDateTime: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(), // yesterday
            status: PartyPlanStatus.ACTIVE,
            visibility: PartyPlanVisibility.PUBLIC,
            depositAmount: 99,
            hostPaymentStatus: PartyPlanPaymentStatus.PAID,
            isLive: true,
            lifecycleStatus: PartyPlanLifecycleStatus.POSTED,
            paymentStatus: 'paid',
            foodPreference: 'Both',
            drinkPreference: 'Both',
            paymentType: PartyPlanPaymentType.SPLIT,
            showProfilePhoto: true,
            showHostName: true,
            showVenueDetails: true,
            showDateDetails: true,
            expiresAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
        } as any);

        const feedRes = await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active' })
            .expect(200);

        const ids: string[] = (feedRes.body.data ?? []).map((p: any) => p.id);
        expect(ids).not.toContain(expired.id);
    });

    // ─── 3.8  Non-invited user cannot join a private plan ─────────────────────

    test('3.8 — A non-invited user gets 403 when attempting to join a private plan', async () => {
        const privatePaid = await createPaidPlan(hostA.id, venueId, {
            visibility: PartyPlanVisibility.PRIVATE,
            selectedUsers: [hostB.id], // only hostB is invited, not joiner
        });

        const res = await request(app)
            .post(`/api/mobile/party-plans/${privatePaid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(403);

        expect(res.body.success).toBe(false);
    });

    // ─── 3.9  Accept request on already-matched plan returns 409 ─────────────

    test('3.9 — Accepting a request on a plan that already has an accepted partner returns 409', async () => {
        const paid = await createPaidPlan(hostA.id, venueId);

        // Joiner sends request
        const reqRes = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${joiner.token}`)
            .send({ userId: joiner.id })
            .expect(201);
        const reqId = reqRes.body.data.id;

        // hostB sends another request
        const reqBRes = await request(app)
            .post(`/api/mobile/party-plans/${paid.id}/requests`)
            .set('Authorization', `Bearer ${hostB.token}`)
            .send({ userId: hostB.id });

        // Accept joiner's request
        await request(app)
            .post(`/api/mobile/party-plans/requests/${reqId}/accept`)
            .set('Authorization', `Bearer ${hostA.token}`)
            .send({ userId: hostA.id })
            .expect(200);

        // Try to also accept hostB's request (should fail - plan locked)
        if (reqBRes.status === 201) {
            const reqBId = reqBRes.body.data.id;
            const res = await request(app)
                .post(`/api/mobile/party-plans/requests/${reqBId}/accept`)
                .set('Authorization', `Bearer ${hostA.token}`)
                .send({ userId: hostA.id });

            // Should be 400 or 409 — plan is locked
            expect([400, 409]).toContain(res.status);
            expect(res.body.success).toBe(false);
        }
    });

    // ─── 3.10  GET /party-plans responds within 2000ms even with pagination ───

    test('3.10 — GET /api/mobile/party-plans?page=1&limit=20 responds within 2000ms', async () => {
        const start = Date.now();
        await request(app)
            .get('/api/mobile/party-plans')
            .query({ status: 'active', page: '1', limit: '20' })
            .expect(200);
        const elapsed = Date.now() - start;

        expect(elapsed).toBeLessThan(2000);
    });

    // ─── 3.11  getPlansByUser for another user only returns that user's plans ──

    test('3.11 — GET /party-plans/user/:userId only returns plans belonging to that specific user', async () => {
        const paidA = await createPaidPlan(hostA.id, venueId);
        const paidB = await createPaidPlan(hostB.id, venueId);

        const resA = await request(app)
            .get(`/api/mobile/party-plans/user/${hostA.id}`)
            .expect(200);

        const idsA: string[] = (resA.body.data ?? []).map((p: any) => p.id);
        expect(idsA).toContain(paidA.id);
        expect(idsA).not.toContain(paidB.id);
    });
});
